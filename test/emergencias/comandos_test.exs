defmodule Emergencias.ComandosTest do
  use ExUnit.Case, async: false

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

    assert {:error, mensaje} = Comandos.ejecutar(usuario, "register_zone #{unico("Z")} Norte alto")
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

  test "comando desconocido" do
    usuario = unico("d")
    {:ok, _, _} = Comandos.ejecutar(nil, "connect #{usuario} 1234 ciudadano centro")

    assert {:error, mensaje} = Comandos.ejecutar(usuario, "volar")
    assert mensaje =~ "desconocido"

    Comandos.ejecutar(usuario, "disconnect")
  end
end
