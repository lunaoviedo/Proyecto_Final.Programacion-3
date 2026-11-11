defmodule Emergencias.Mascotas.ServidorMascotasTest do
  use ExUnit.Case, async: true

  alias Emergencias.Mascotas.ServidorMascotas
  alias Emergencias.Persistencia

  setup do
    sufijo = System.unique_integer([:positive])
    entidad = :"mascotas_prueba_#{sufijo}"
    nombre = :"servidor_mascotas_prueba_#{sufijo}"

    on_exit(fn ->
      File.rm_rf(Persistencia.ruta_archivo(entidad))
      File.rm_rf(Persistencia.ruta_archivo(entidad) <> ".tmp")
    end)

    start_supervised!({ServidorMascotas, name: nombre, entidad: entidad})

    %{servidor: nombre, entidad: entidad}
  end

  defp atributos(extra \\ %{}) do
    Map.merge(
      %{
        tipo: "perdida",
        especie: "Perro",
        nombre: "Luna",
        color: "Negra",
        tamano: "mediano",
        zona: "zona_norte",
        contacto: "3001234567",
        caracteristicas: ["Collar rojo"]
      },
      extra
    )
  end

  defp encontrada(extra \\ %{}),
    do: atributos(Map.merge(%{tipo: "encontrada", nombre: "desconocido"}, extra))

  defp ids({:ok, lista}), do: Enum.map(lista, & &1.id)

  defp en_paralelo(cantidad, funcion) do
    1..cantidad
    |> Task.async_stream(funcion, max_concurrency: cantidad, timeout: 15_000)
    |> Enum.map(fn {:ok, resultado} -> resultado end)
  end

  describe "registrar/2" do
    test "genera identificadores consecutivos cuando no se indican", %{servidor: s} do
      assert {:ok, %{id: "MA001", estado: :activa}} = ServidorMascotas.registrar(atributos(), s)
      assert {:ok, %{id: "MA002"}} = ServidorMascotas.registrar(encontrada(), s)
    end

    test "respeta un identificador indicado y no lo repite", %{servidor: s} do
      assert {:ok, %{id: "MA050"}} = ServidorMascotas.registrar(atributos(%{id: "MA050"}), s)

      assert {:error, :id_existente} = ServidorMascotas.registrar(atributos(%{id: "MA050"}), s)
    end

    test "rechaza datos inválidos sin modificar el estado", %{servidor: s} do
      assert {:error, :especie_invalida} =
               ServidorMascotas.registrar(atributos(%{especie: ""}), s)

      assert {:error, :tamano_invalido} = ServidorMascotas.registrar(atributos(%{tamano: "x"}), s)
      assert {:error, :atributos_invalidos} = ServidorMascotas.registrar("no es un mapa", s)
      assert {:error, :atributos_invalidos} = ServidorMascotas.registrar(nil, s)

      assert {:ok, []} = ServidorMascotas.consultar([], s)
    end

    test "guarda cada reporte en el archivo", %{servidor: s, entidad: entidad} do
      {:ok, _} = ServidorMascotas.registrar(atributos(), s)
      {:ok, _} = ServidorMascotas.registrar(encontrada(), s)

      assert {:ok, [%{"id" => "MA001"}, %{"id" => "MA002"}]} = Persistencia.cargar(entidad)
    end
  end

  describe "obtener/2 y consultar/2" do
    test "obtiene un reporte existente y falla con uno inexistente", %{servidor: s} do
      {:ok, _} = ServidorMascotas.registrar(atributos(), s)

      assert {:ok, %{id: "MA001"}} = ServidorMascotas.obtener("MA001", s)
      assert {:error, :reporte_no_encontrado} = ServidorMascotas.obtener("MA999", s)
      assert {:error, :reporte_no_encontrado} = ServidorMascotas.obtener(nil, s)
    end

    test "consulta por especie, zona y estado", %{servidor: s} do
      {:ok, _} = ServidorMascotas.registrar(atributos(), s)
      {:ok, _} = ServidorMascotas.registrar(encontrada(%{zona: "zona_sur"}), s)
      {:ok, _} = ServidorMascotas.registrar(atributos(%{especie: "Gato"}), s)

      assert ids(ServidorMascotas.consultar([], s)) == ["MA001", "MA002", "MA003"]
      assert ids(ServidorMascotas.consultar([especie: "perro"], s)) == ["MA001", "MA002"]
      assert ids(ServidorMascotas.consultar([zona: "zona_sur"], s)) == ["MA002"]
      assert ids(ServidorMascotas.consultar([estado: "resuelta"], s)) == []
    end

    test "rechaza filtros inválidos", %{servidor: s} do
      assert {:error, {:filtro_invalido, :color}} = ServidorMascotas.consultar([color: "x"], s)
      assert {:error, :estado_invalido} = ServidorMascotas.consultar([estado: "rara"], s)
      assert {:error, :filtros_invalidos} = ServidorMascotas.consultar("no es lista", s)
    end
  end

  describe "buscar_coincidencias/1" do
    test "sin reportes retorna lista vacía", %{servidor: s} do
      assert [] = ServidorMascotas.buscar_coincidencias(s)
    end

    test "encuentra la pareja y deja de proponerla una vez asociada", %{servidor: s} do
      {:ok, _} = ServidorMascotas.registrar(atributos(), s)
      {:ok, _} = ServidorMascotas.registrar(encontrada(), s)

      assert [%{perdida: "MA001", encontrada: "MA002", puntaje: 105}] =
               ServidorMascotas.buscar_coincidencias(s)

      {:ok, _} = ServidorMascotas.asociar("MA001", "MA002", s)
      assert [] = ServidorMascotas.buscar_coincidencias(s)
    end
  end

  describe "asociar/3, descartar/2 y confirmar/3" do
    setup %{servidor: s} do
      {:ok, _} = ServidorMascotas.registrar(atributos(), s)
      {:ok, _} = ServidorMascotas.registrar(encontrada(), s)
      :ok
    end

    test "asociar enlaza ambos reportes", %{servidor: s} do
      assert {:ok, {a, b}} = ServidorMascotas.asociar("MA001", "MA002", s)

      assert a.estado == :posible_coincidencia and a.coincidencia_con == "MA002"
      assert b.estado == :posible_coincidencia and b.coincidencia_con == "MA001"
      assert {:ok, %{estado: :posible_coincidencia}} = ServidorMascotas.obtener("MA001", s)
    end

    test "rechaza asociar el mismo reporte, inexistentes o del mismo tipo", %{servidor: s} do
      {:ok, _} = ServidorMascotas.registrar(atributos(), s)

      assert {:error, :mismo_reporte} = ServidorMascotas.asociar("MA001", "MA001", s)
      assert {:error, :reporte_no_encontrado} = ServidorMascotas.asociar("MA001", "MA999", s)
      assert {:error, :tipos_iguales} = ServidorMascotas.asociar("MA001", "MA003", s)
    end

    test "descartar devuelve ambos reportes a activa", %{servidor: s} do
      {:ok, _} = ServidorMascotas.asociar("MA001", "MA002", s)

      assert {:ok, {a, b}} = ServidorMascotas.descartar("MA001", s)
      assert a.estado == :activa and a.coincidencia_con == nil
      assert b.estado == :activa and b.coincidencia_con == nil
      assert {:error, :sin_coincidencia_pendiente} = ServidorMascotas.descartar("MA001", s)
    end

    test "confirmar cierra ambos reportes y no se puede repetir", %{servidor: s} do
      {:ok, _} = ServidorMascotas.asociar("MA001", "MA002", s)

      assert {:ok, {a, b}} = ServidorMascotas.confirmar("MA001", "MA002", s)
      assert a.estado == :resuelta and b.estado == :resuelta

      assert {:error, :reporte_resuelto} = ServidorMascotas.confirmar("MA001", "MA002", s)
      assert {:error, :reporte_resuelto} = ServidorMascotas.descartar("MA001", s)
    end
  end

  describe "persistencia" do
    test "recupera los reportes y sus estados al reiniciar", %{servidor: s, entidad: entidad} do
      {:ok, _} = ServidorMascotas.registrar(atributos(), s)
      {:ok, _} = ServidorMascotas.registrar(encontrada(), s)
      {:ok, _} = ServidorMascotas.confirmar("MA001", "MA002", s)

      stop_supervised!(ServidorMascotas)
      start_supervised!({ServidorMascotas, name: s, entidad: entidad})

      assert {:ok, %{estado: :resuelta, coincidencia_con: "MA002"}} =
               ServidorMascotas.obtener("MA001", s)

      assert {:ok, %{id: "MA003"}} = ServidorMascotas.registrar(atributos(), s)
    end

    test "no inicia si el archivo contiene una línea que no es JSON" do
      Process.flag(:trap_exit, true)
      entidad = :"mascotas_corrupta_#{System.unique_integer([:positive])}"
      ruta = Persistencia.ruta_archivo(entidad)
      File.mkdir_p!(Path.dirname(ruta))
      File.write!(ruta, "esto no es json\n")
      on_exit(fn -> File.rm(ruta) end)

      assert {:error, {:persistencia, {:linea_invalida, 1}}} =
               ServidorMascotas.start_link(name: :servidor_corrupto, entidad: entidad)
    end

    test "no inicia si un registro no corresponde a una mascota" do
      Process.flag(:trap_exit, true)
      entidad = :"mascotas_incompleta_#{System.unique_integer([:positive])}"
      ruta = Persistencia.ruta_archivo(entidad)
      File.mkdir_p!(Path.dirname(ruta))
      File.write!(ruta, ~s({"id": "MA001"}\n))
      on_exit(fn -> File.rm(ruta) end)

      assert {:error, {:persistencia, :registro_invalido}} =
               ServidorMascotas.start_link(name: :servidor_incompleto, entidad: entidad)
    end

    test "si no se puede guardar, el estado no cambia", %{servidor: s, entidad: entidad} do
      {:ok, _} = ServidorMascotas.registrar(atributos(), s)

      # Un directorio en lugar del archivo impide el renombrado final.
      File.rm!(Persistencia.ruta_archivo(entidad))
      File.mkdir_p!(Persistencia.ruta_archivo(entidad))

      assert {:error, {:persistencia, _}} = ServidorMascotas.registrar(encontrada(), s)
      assert ids(ServidorMascotas.consultar([], s)) == ["MA001"]
    end
  end

  describe "concurrencia" do
    test "50 registros simultáneos sin identificador no repiten ninguno", %{servidor: s} do
      resultados = en_paralelo(50, fn _ -> ServidorMascotas.registrar(atributos(), s) end)

      assert Enum.all?(resultados, &match?({:ok, _}, &1))

      identificadores = Enum.map(resultados, fn {:ok, m} -> m.id end)
      assert length(Enum.uniq(identificadores)) == 50
      assert {:ok, lista} = ServidorMascotas.consultar([], s)
      assert length(lista) == 50
    end

    test "20 confirmaciones simultáneas del mismo reporte: solo una se acepta", %{servidor: s} do
      {:ok, _} = ServidorMascotas.registrar(atributos(), s)
      for _ <- 1..20, do: {:ok, _} = ServidorMascotas.registrar(encontrada(), s)

      resultados =
        en_paralelo(20, fn i ->
          ServidorMascotas.confirmar("MA001", "MA#{String.pad_leading("#{i + 1}", 3, "0")}", s)
        end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :reporte_resuelto})) == 19

      assert {:ok, [_]} = ServidorMascotas.consultar([estado: "resuelta", tipo: "perdida"], s)
      assert {:ok, resueltas} = ServidorMascotas.consultar([estado: "resuelta"], s)
      assert length(resueltas) == 2
    end

    test "asociaciones simultáneas de un reporte con varios candidatos: solo una se acepta",
         %{servidor: s} do
      {:ok, _} = ServidorMascotas.registrar(atributos(), s)
      for _ <- 1..10, do: {:ok, _} = ServidorMascotas.registrar(encontrada(), s)

      resultados =
        en_paralelo(10, fn i ->
          ServidorMascotas.asociar("MA001", "MA#{String.pad_leading("#{i + 1}", 3, "0")}", s)
        end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :ya_asociado_a_otro})) == 9
    end
  end
end
