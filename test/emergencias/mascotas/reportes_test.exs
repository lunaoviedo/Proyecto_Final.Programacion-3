defmodule Emergencias.Mascotas.ReportesTest do
  use ExUnit.Case, async: true

  alias Emergencias.Mascotas.Reportes

  doctest Emergencias.Mascotas.Reportes

  defp atributos(extra \\ %{}) do
    Map.merge(
      %{
        id: "MA001",
        tipo: "perdida",
        especie: "Perro",
        nombre: "Luna",
        color: "Negra",
        tamano: "mediano",
        zona: "zona_norte",
        contacto: "3001234567",
        caracteristicas: ["Collar rojo", "oreja caida"]
      },
      extra
    )
  end

  # MA001 perdida/perro/norte, MA002 encontrada/perro/norte, MA003 perdida/gato/sur
  defp reportes_base do
    {:ok, r1, _} = Reportes.registrar(%{}, atributos())

    {:ok, r2, _} =
      Reportes.registrar(r1, atributos(%{id: "MA002", tipo: "encontrada", nombre: "desconocido"}))

    {:ok, r3, _} =
      Reportes.registrar(r2, atributos(%{id: "MA003", especie: "gato", zona: "zona_sur"}))

    r3
  end

  defp ids({:ok, lista}), do: Enum.map(lista, & &1.id)

  describe "registrar/2 con datos válidos" do
    test "crea un reporte activo y normaliza los textos" do
      assert {:ok, reportes, mascota} = Reportes.registrar(%{}, atributos())

      assert mascota.id == "MA001"
      assert mascota.tipo == :perdida
      assert mascota.especie == "perro"
      assert mascota.color == "negra"
      assert mascota.nombre == "Luna"
      assert mascota.tamano == :mediano
      assert mascota.caracteristicas == ["collar rojo", "oreja caida"]
      assert mascota.estado == :activa
      assert mascota.coincidencia_con == nil
      assert reportes["MA001"] == mascota
    end

    test "acepta los tipos lost y found" do
      assert {:ok, _, %{tipo: :perdida}} = Reportes.registrar(%{}, atributos(%{tipo: "lost"}))
      assert {:ok, _, %{tipo: :encontrada}} = Reportes.registrar(%{}, atributos(%{tipo: "found"}))
    end

    test "un nombre vacío, omitido o desconocido se guarda como nil" do
      assert {:ok, _, %{nombre: nil}} =
               Reportes.registrar(%{}, atributos(%{nombre: "desconocido"}))

      assert {:ok, _, %{nombre: nil}} = Reportes.registrar(%{}, atributos(%{nombre: "  "}))
      assert {:ok, _, %{nombre: nil}} = Reportes.registrar(%{}, Map.delete(atributos(), :nombre))
    end

    test "acepta el tamaño con ñ" do
      assert {:ok, _, %{tamano: :pequeno}} =
               Reportes.registrar(%{}, atributos(%{tamano: "pequeño"}))
    end

    test "elimina características vacías y repetidas" do
      assert {:ok, _, mascota} =
               Reportes.registrar(
                 %{},
                 atributos(%{caracteristicas: ["Cojea", " cojea ", "", "manchas"]})
               )

      assert mascota.caracteristicas == ["cojea", "manchas"]
    end
  end

  describe "registrar/2 con datos inválidos" do
    test "rechaza un identificador repetido" do
      {:ok, reportes, _} = Reportes.registrar(%{}, atributos())
      assert {:error, :id_existente} = Reportes.registrar(reportes, atributos())
    end

    test "rechaza campos obligatorios inválidos" do
      assert {:error, :id_invalido} = Reportes.registrar(%{}, atributos(%{id: ""}))
      assert {:error, :tipo_invalido} = Reportes.registrar(%{}, atributos(%{tipo: "otro"}))
      assert {:error, :especie_invalida} = Reportes.registrar(%{}, atributos(%{especie: ""}))
      assert {:error, :color_invalido} = Reportes.registrar(%{}, atributos(%{color: "   "}))
      assert {:error, :tamano_invalido} = Reportes.registrar(%{}, atributos(%{tamano: "enorme"}))
      assert {:error, :zona_invalida} = Reportes.registrar(%{}, atributos(%{zona: nil}))
      assert {:error, :contacto_invalido} = Reportes.registrar(%{}, atributos(%{contacto: ""}))
    end

    test "rechaza nombre y características con tipo incorrecto" do
      assert {:error, :nombre_invalido} = Reportes.registrar(%{}, atributos(%{nombre: 123}))

      assert {:error, :caracteristicas_invalidas} =
               Reportes.registrar(%{}, atributos(%{caracteristicas: [1, 2]}))

      assert {:error, :caracteristicas_invalidas} =
               Reportes.registrar(%{}, atributos(%{caracteristicas: "no es lista"}))
    end
  end

  describe "siguiente_id/1" do
    test "continúa la numeración" do
      assert Reportes.siguiente_id(reportes_base()) == "MA004"
    end

    test "evita identificadores ya ocupados" do
      assert Reportes.siguiente_id(%{"MA002" => :cualquiera}) == "MA003"
    end
  end

  describe "consultar/2" do
    test "sin filtros retorna todo ordenado por identificador" do
      assert ids(Reportes.consultar(reportes_base())) == ["MA001", "MA002", "MA003"]
    end

    test "filtra por especie sin distinguir mayúsculas" do
      assert ids(Reportes.consultar(reportes_base(), especie: "PERRO")) == ["MA001", "MA002"]
    end

    test "combina varios filtros" do
      assert ids(Reportes.consultar(reportes_base(), zona: "zona_norte", tipo: "encontrada")) == [
               "MA002"
             ]
    end

    test "filtra por estado" do
      assert ids(Reportes.consultar(reportes_base(), estado: "activa")) == [
               "MA001",
               "MA002",
               "MA003"
             ]

      assert ids(Reportes.consultar(reportes_base(), estado: "resuelta")) == []
    end

    test "sin coincidencias o sin reportes retorna lista vacía" do
      assert {:ok, []} = Reportes.consultar(reportes_base(), especie: "loro")
      assert {:ok, []} = Reportes.consultar(%{})
    end

    test "rechaza filtros desconocidos o con valores inválidos" do
      assert {:error, {:filtro_invalido, :color}} =
               Reportes.consultar(reportes_base(), color: "negra")

      assert {:error, :estado_invalido} = Reportes.consultar(reportes_base(), estado: "rara")
    end
  end

  describe "transicion_valida?/2" do
    test "permite las transiciones del ciclo de vida" do
      assert Reportes.transicion_valida?(:activa, :posible_coincidencia)
      assert Reportes.transicion_valida?(:posible_coincidencia, :activa)
      assert Reportes.transicion_valida?(:posible_coincidencia, :resuelta)
      assert Reportes.transicion_valida?(:activa, :resuelta)
    end

    test "rechaza salir de resuelta o repetir un estado" do
      refute Reportes.transicion_valida?(:resuelta, :activa)
      refute Reportes.transicion_valida?(:resuelta, :posible_coincidencia)
      refute Reportes.transicion_valida?(:posible_coincidencia, :posible_coincidencia)
    end
  end

  describe "asociar/3" do
    test "enlaza ambos reportes como posible coincidencia" do
      assert {:ok, nuevos, {a, b}} = Reportes.asociar(reportes_base(), "MA001", "MA002")

      assert a.estado == :posible_coincidencia and a.coincidencia_con == "MA002"
      assert b.estado == :posible_coincidencia and b.coincidencia_con == "MA001"
      assert nuevos["MA001"] == a
      assert nuevos["MA003"].estado == :activa
    end

    test "rechaza el mismo reporte, reportes inexistentes y tipos iguales" do
      assert {:error, :mismo_reporte} = Reportes.asociar(reportes_base(), "MA001", "MA001")

      assert {:error, :reporte_no_encontrado} =
               Reportes.asociar(reportes_base(), "MA001", "MA999")

      assert {:error, :tipos_iguales} = Reportes.asociar(reportes_base(), "MA001", "MA003")
    end

    test "rechaza asociar un reporte que ya tiene otra pareja" do
      {:ok, reportes, _} = Reportes.asociar(reportes_base(), "MA001", "MA002")

      {:ok, reportes, _} =
        Reportes.registrar(reportes, atributos(%{id: "MA004", tipo: "encontrada"}))

      assert {:error, :ya_asociado_a_otro} = Reportes.asociar(reportes, "MA001", "MA004")
    end

    test "rechaza asociar dos veces la misma pareja" do
      {:ok, reportes, _} = Reportes.asociar(reportes_base(), "MA001", "MA002")

      assert {:error, {:transicion_invalida, :posible_coincidencia, :posible_coincidencia}} =
               Reportes.asociar(reportes, "MA001", "MA002")
    end
  end

  describe "confirmar/3" do
    test "cierra una pareja que estaba como posible coincidencia" do
      {:ok, reportes, _} = Reportes.asociar(reportes_base(), "MA001", "MA002")

      assert {:ok, nuevos, {a, b}} = Reportes.confirmar(reportes, "MA001", "MA002")
      assert a.estado == :resuelta and b.estado == :resuelta
      assert nuevos["MA001"].coincidencia_con == "MA002"
    end

    test "permite confirmar dos reportes activos sin asociación previa" do
      assert {:ok, _, {a, b}} = Reportes.confirmar(reportes_base(), "MA001", "MA002")
      assert a.estado == :resuelta and a.coincidencia_con == "MA002"
      assert b.estado == :resuelta and b.coincidencia_con == "MA001"
    end

    test "no permite cerrar dos veces un reporte" do
      {:ok, reportes, _} = Reportes.confirmar(reportes_base(), "MA001", "MA002")

      {:ok, reportes, _} =
        Reportes.registrar(reportes, atributos(%{id: "MA004", tipo: "encontrada"}))

      assert {:error, :reporte_resuelto} = Reportes.confirmar(reportes, "MA001", "MA002")
      assert {:error, :reporte_resuelto} = Reportes.confirmar(reportes, "MA001", "MA004")
    end

    test "no permite confirmar con un reporte asociado a otro" do
      {:ok, reportes, _} = Reportes.asociar(reportes_base(), "MA001", "MA002")

      {:ok, reportes, _} =
        Reportes.registrar(reportes, atributos(%{id: "MA004", tipo: "encontrada"}))

      assert {:error, :ya_asociado_a_otro} = Reportes.confirmar(reportes, "MA001", "MA004")
    end
  end

  describe "descartar/2" do
    test "devuelve ambos reportes a activa y quita el enlace" do
      {:ok, reportes, _} = Reportes.asociar(reportes_base(), "MA001", "MA002")

      assert {:ok, nuevos, {a, b}} = Reportes.descartar(reportes, "MA001")
      assert a.estado == :activa and a.coincidencia_con == nil
      assert b.estado == :activa and b.coincidencia_con == nil
      assert nuevos["MA002"] == b
    end

    test "permite asociar de nuevo con otro reporte después de descartar" do
      {:ok, reportes, _} = Reportes.asociar(reportes_base(), "MA001", "MA002")
      {:ok, reportes, _} = Reportes.descartar(reportes, "MA001")

      {:ok, reportes, _} =
        Reportes.registrar(reportes, atributos(%{id: "MA004", tipo: "encontrada"}))

      assert {:ok, _, {a, _}} = Reportes.asociar(reportes, "MA001", "MA004")
      assert a.coincidencia_con == "MA004"
    end

    test "rechaza descartar sin coincidencia pendiente, resuelto o inexistente" do
      assert {:error, :sin_coincidencia_pendiente} = Reportes.descartar(reportes_base(), "MA001")
      assert {:error, :reporte_no_encontrado} = Reportes.descartar(reportes_base(), "MA999")

      {:ok, reportes, _} = Reportes.confirmar(reportes_base(), "MA001", "MA002")
      assert {:error, :reporte_resuelto} = Reportes.descartar(reportes, "MA001")
    end
  end

  describe "a_registro/1 y de_registro/1" do
    test "recuperan el mismo reporte tras pasar por JSON" do
      {:ok, reportes, _} = Reportes.asociar(reportes_base(), "MA001", "MA002")
      original = reportes["MA001"]

      {:ok, leido} = original |> Reportes.a_registro() |> JSON.encode!() |> JSON.decode()

      assert {:ok, ^original} = Reportes.de_registro(leido)
    end

    test "conserva un nombre nulo" do
      {:ok, _, original} =
        Reportes.registrar(%{}, atributos(%{nombre: "desconocido"}))

      {:ok, leido} = original |> Reportes.a_registro() |> JSON.encode!() |> JSON.decode()

      assert {:ok, %{nombre: nil}} = Reportes.de_registro(leido)
    end

    test "rechaza registros incompletos o con valores inválidos" do
      assert {:error, :registro_invalido} = Reportes.de_registro(%{"id" => "MA001"})

      registro = Reportes.a_registro(reportes_base()["MA001"])

      assert {:error, :tipo_invalido} = Reportes.de_registro(%{registro | "tipo" => "x"})
      assert {:error, :estado_invalido} = Reportes.de_registro(%{registro | "estado" => "rara"})
      assert {:error, :tamano_invalido} = Reportes.de_registro(%{registro | "tamano" => "enorme"})

      assert {:error, :caracteristicas_invalidas} =
               Reportes.de_registro(%{registro | "caracteristicas" => "no lista"})
    end
  end
end
