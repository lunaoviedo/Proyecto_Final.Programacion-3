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

  test "conflicto concurrente en inventario: 30 y 25 litros sobre 50, solo uno se acepta" do
    codigo = unico("AGUA")

    recurso = %Emergencias.Recursos.Recurso{
      codigo: codigo,
      nombre: "Agua purificada",
      categoria: "hidratacion",
      cantidad: 50,
      unidad: "litros",
      ubicacion: "zona_centro"
    }

    Emergencias.Recursos.ServidorInventario.registrar_recurso(recurso)

    # Proceso 1: Intenta descontar 30 litros
    tarea1 = Task.async(fn ->
      Emergencias.Recursos.ServidorInventario.descontar_recurso(codigo, 30)
    end)

    # Proceso 2: Intenta descontar 25 litros
    tarea2 = Task.async(fn ->
      Emergencias.Recursos.ServidorInventario.descontar_recurso(codigo, 25)
    end)

    resultado1 = Task.await(tarea1)
    resultado2 = Task.await(tarea2)
    resultados = [resultado1, resultado2]

    # Verificamos que uno pase y el otro falle por falta de stock
    assert :ok in resultados
    assert {:error, :stock_insuficiente} in resultados

    # Verificamos que el inventario no quede en negativo
    [recurso_final] =
      Emergencias.Recursos.ServidorInventario.listar_recursos()
      |> Enum.filter(&(&1.codigo == codigo))

    assert recurso_final.cantidad in [20, 25]
  end
end
