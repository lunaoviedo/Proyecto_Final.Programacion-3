defmodule Emergencias.ConcurrenciaTest do
  use ExUnit.Case, async: false

  alias Emergencias.Usuarios.ServidorSesiones
  alias Emergencias.Zonas.{ServidorZonas, ArbolZonas}

  defp unico(prefijo), do: prefijo <> Base.encode16(:crypto.strong_rand_bytes(6))

  defp en_paralelo(cantidad, funcion) do
    1..cantidad
    |> Task.async_stream(funcion, max_concurrency: cantidad, timeout: 15_000)
    |> Enum.map(fn {:ok, resultado} -> resultado end)
  end

  test "20 registros simultáneos de la misma zona: solo uno se acepta" do
    codigo = unico("ZC")

    resultados =
      en_paralelo(20, fn i -> ServidorZonas.registrar_zona(codigo, "Zona #{i}", "alto") end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert Enum.count(resultados, &(&1 == {:error, :codigo_existente})) == 19
    assert Enum.count(ServidorZonas.listar_zonas(), &(&1.codigo == codigo)) == 1
  end

  test "10 conexiones simultáneas del mismo usuario: solo una sesión" do
    usuario = unico("u")

    resultados =
      en_paralelo(10, fn _ ->
        ServidorSesiones.conectar(usuario, "1234", "ciudadano", "centro")
      end)

    assert Enum.count(resultados, &match?({:ok, _, _}, &1)) == 1
    assert Enum.count(resultados, &(&1 == {:error, :ya_conectado})) == 9

    ServidorSesiones.desconectar(usuario)
  end

  test "50 sectores distintos registrados a la vez: no se pierde ninguno" do
    zona = unico("ZS")
    {:ok, _} = ServidorZonas.registrar_zona(zona, "Zona de prueba", "alto")

    resultados =
      en_paralelo(50, fn i ->
        ServidorZonas.registrar_sector(zona, "#{zona}-s#{i}", "Sector #{i}", i)
      end)

    assert Enum.all?(resultados, &match?({:ok, _}, &1))

    {:ok, guardada} = ServidorZonas.obtener_zona(zona)
    assert length(guardada.sectores) == 50
    assert ArbolZonas.total_afectados(guardada) == Enum.sum(1..50)
  end
end
