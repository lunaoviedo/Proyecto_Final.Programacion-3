defmodule Emergencias.ComandosTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Emergencias.Comandos

  defp unico(prefijo) do
    "#{prefijo}#{System.system_time(:microsecond)}#{rem(System.unique_integer([:positive]), 100)}"
  end

  test "flujo completo de un coordinador" do
    usuario = unico("u")
    zona = unico("Z")
    sector = unico("S")

    assert {:ok, _, ^usuario} =
             Comandos.ejecutar(nil, "connect #{usuario} 1234 coordinador centro")

    assert {:ok, mensaje, ^usuario} =
             Comandos.ejecutar(usuario, ~s(register_zone #{zona} "Zona Norte" critico 100))

    assert mensaje =~ "registrada"

    assert {:ok, _, _} =
             Comandos.ejecutar(usuario, ~s(register_sector #{zona} #{sector} "Sector 3" 50))

    assert {:ok, estado, _} = Comandos.ejecutar(usuario, "zone_status #{zona}")
    assert estado =~ "150"

    assert {:ok, _, nil} = Comandos.ejecutar(usuario, "disconnect")
  end

  test "sin sesión no se puede ejecutar nada" do
    assert {:error, mensaje} = Comandos.ejecutar(nil, "list_zones")
    assert mensaje =~ "conectarte"
  end

  test "un ciudadano no puede registrar zonas" do
    usuario = unico("c")
    {:ok, _, _} = Comandos.ejecutar(nil, "connect #{usuario} 1234 ciudadano centro")

    assert {:error, mensaje} =
             Comandos.ejecutar(usuario, "register_zone #{unico("Z")} Norte alto")

    assert mensaje =~ "permiso"

    Comandos.ejecutar(usuario, "disconnect")
  end

  test "contraseña incorrecta y argumentos inválidos" do
    usuario = unico("p")
    {:ok, _, _} = Comandos.ejecutar(nil, "connect #{usuario} 1234 ciudadano centro")
    {:ok, _, nil} = Comandos.ejecutar(usuario, "disconnect")

    assert {:error, mensaje} = Comandos.ejecutar(nil, "connect #{usuario} mala ciudadano centro")
    assert mensaje =~ "incorrectos"

    assert {:error, "Uso: connect" <> _} = Comandos.ejecutar(nil, "connect solo_usuario")
  end

  describe "una falla interna no tumba la consola" do
    setup do
      usuario = unico("r")
      {:ok, _, _} = Comandos.ejecutar(nil, "connect #{usuario} 1234 ciudadano centro")
      on_exit(fn -> Comandos.ejecutar(usuario, "disconnect") end)
      %{usuario: usuario}
    end

    test "una excepción en el comando se devuelve como error", %{usuario: usuario} do
      assert {:error, "Error interno: " <> detalle} =
               Comandos.ejecutar(usuario, "list_needs estado:no_existe_#{unico("e")}")

      assert detalle =~ "ArgumentError"
      assert {:ok, _, ^usuario} = Comandos.ejecutar(usuario, "list_zones")
    end

    test "la caída de un servidor se devuelve como error", %{usuario: usuario} do
      {:ok, _, _} =
        Comandos.ejecutar(
          usuario,
          ~s(register_need #{unico("n")} agua "Agua potable" 10 centro 1 #{usuario})
        )

      capture_log(fn ->
        assert {:error, "Error interno: " <> detalle} =
                 Comandos.ejecutar(usuario, "list_needs prioridad:abc")

        assert detalle =~ "un servicio falló"
      end)

      esperar_servidor(Emergencias.Recursos.ServidorNecesidades)
      assert {:ok, _, ^usuario} = Comandos.ejecutar(usuario, "list_needs")
    end
  end

  defp esperar_servidor(nombre, intentos \\ 50) do
    cond do
      is_pid(Process.whereis(nombre)) -> :ok
      intentos == 0 -> flunk("#{inspect(nombre)} no se reinició")
      true -> Process.sleep(20) && esperar_servidor(nombre, intentos - 1)
    end
  end

  test "comando desconocido" do
    usuario = unico("d")
    {:ok, _, _} = Comandos.ejecutar(nil, "connect #{usuario} 1234 ciudadano centro")

    assert {:error, mensaje} = Comandos.ejecutar(usuario, "volar")
    assert mensaje =~ "desconocido"

    Comandos.ejecutar(usuario, "disconnect")
  end
end
