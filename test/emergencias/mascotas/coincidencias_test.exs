defmodule Emergencias.Mascotas.CoincidenciasTest do
  use ExUnit.Case, async: true

  alias Emergencias.Mascotas.{Coincidencias, Mascota, Reportes}

  doctest Emergencias.Mascotas.Coincidencias

  defp perdida(extra \\ %{}) do
    struct!(
      Mascota,
      Map.merge(
        %{
          id: "MA001",
          tipo: :perdida,
          especie: "perro",
          nombre: "Luna",
          color: "negra",
          tamano: :mediano,
          zona: "zona_norte",
          contacto: "3001234567",
          caracteristicas: ["collar rojo", "oreja caida"]
        },
        extra
      )
    )
  end

  defp encontrada(extra \\ %{}), do: perdida(Map.merge(%{id: "MA002", tipo: :encontrada}, extra))

  defp indexar(lista), do: Map.new(lista, &{&1.id, &1})

  defp puntos(clave, a, b) do
    {:ok, detalle} = Coincidencias.desglose(a, b)
    Map.fetch!(detalle, clave)
  end

  describe "puntaje/2 y desglose/2" do
    test "dos reportes idénticos obtienen el máximo" do
      assert {:ok, %{color: 40, tamano: 15, zona: 30, nombre: 25, caracteristicas: 20}} =
               Coincidencias.desglose(perdida(), encontrada())

      assert {:ok, 130} = Coincidencias.puntaje(perdida(), encontrada())
      assert Coincidencias.puntaje_maximo() == 130
    end

    test "descarta reportes del mismo tipo" do
      assert {:error, :tipos_iguales} = Coincidencias.desglose(perdida(), perdida(%{id: "MA003"}))
      assert {:error, :tipos_iguales} = Coincidencias.puntaje(perdida(), perdida(%{id: "MA003"}))
    end

    test "descarta especies distintas sin importar el resto" do
      assert {:error, :especies_distintas} =
               Coincidencias.puntaje(perdida(), encontrada(%{especie: "gato"}))
    end

    test "compara la especie sin distinguir mayúsculas" do
      assert {:ok, 130} = Coincidencias.puntaje(perdida(), encontrada(%{especie: "PERRO"}))
    end
  end

  describe "puntos por color y zona" do
    test "suman cuando coinciden, sin distinguir mayúsculas" do
      assert puntos(:color, perdida(), encontrada(%{color: "NEGRA"})) == 40
      assert puntos(:zona, perdida(), encontrada(%{zona: "ZONA_NORTE"})) == 30
    end

    test "no suman cuando difieren" do
      assert puntos(:color, perdida(), encontrada(%{color: "blanca"})) == 0
      assert puntos(:zona, perdida(), encontrada(%{zona: "zona_sur"})) == 0
    end
  end

  describe "puntos por nombre" do
    test "suman cuando ambos lo conocen y coincide, sin distinguir mayúsculas" do
      assert puntos(:nombre, perdida(), encontrada(%{nombre: "LUNA"})) == 25
    end

    test "no suman si el nombre difiere" do
      assert puntos(:nombre, perdida(), encontrada(%{nombre: "Rex"})) == 0
    end

    test "no suman si alguno lo desconoce, y tampoco restan" do
      assert puntos(:nombre, perdida(), encontrada(%{nombre: nil})) == 0
      assert puntos(:nombre, perdida(%{nombre: nil}), encontrada()) == 0
      assert puntos(:nombre, perdida(%{nombre: nil}), encontrada(%{nombre: nil})) == 0
    end
  end

  describe "puntos por tamaño" do
    test "tamaño igual suma el máximo" do
      assert puntos(:tamano, perdida(), encontrada()) == 15
    end

    test "tamaños adyacentes suman la mitad aproximadamente, en ambos sentidos" do
      assert puntos(:tamano, perdida(%{tamano: :pequeno}), encontrada(%{tamano: :mediano})) == 7
      assert puntos(:tamano, perdida(%{tamano: :mediano}), encontrada(%{tamano: :pequeno})) == 7
      assert puntos(:tamano, perdida(%{tamano: :mediano}), encontrada(%{tamano: :grande})) == 7
      assert puntos(:tamano, perdida(%{tamano: :grande}), encontrada(%{tamano: :mediano})) == 7
    end

    test "tamaños opuestos no suman" do
      assert puntos(:tamano, perdida(%{tamano: :pequeno}), encontrada(%{tamano: :grande})) == 0
    end
  end

  describe "puntos por características" do
    test "los mismos rasgos suman el máximo, sin importar orden ni mayúsculas" do
      assert puntos(:caracteristicas, perdida(), encontrada()) == 20

      assert puntos(
               :caracteristicas,
               perdida(),
               encontrada(%{caracteristicas: ["OREJA CAIDA", "Collar Rojo"]})
             ) == 20
    end

    test "rasgos parcialmente compartidos suman en proporción" do
      # 1 en común de 3 distintos: 20 * 1/3 = 6.67, redondeado a 7
      assert puntos(
               :caracteristicas,
               perdida(),
               encontrada(%{caracteristicas: ["collar rojo", "manchas"]})
             ) == 7
    end

    test "rasgos sin nada en común no suman" do
      assert puntos(:caracteristicas, perdida(), encontrada(%{caracteristicas: ["cojea"]})) == 0
    end

    test "dos listas vacías no suman ni fallan" do
      assert puntos(
               :caracteristicas,
               perdida(%{caracteristicas: []}),
               encontrada(%{caracteristicas: []})
             ) == 0
    end
  end

  describe "buscar/1" do
    test "sin reportes retorna lista vacía" do
      assert [] = Coincidencias.buscar(%{})
    end

    test "encuentra una pareja que supera el umbral con su desglose" do
      assert [coincidencia] = Coincidencias.buscar(indexar([perdida(), encontrada()]))

      assert coincidencia.perdida == "MA001"
      assert coincidencia.encontrada == "MA002"
      assert coincidencia.puntaje == 130
      assert coincidencia.desglose.color == 40
    end

    test "incluye una pareja que alcanza exactamente el umbral" do
      # color 40 + características 20 = 60; tamaño opuesto, zona distinta, sin nombre
      p = perdida(%{tamano: :pequeno})
      e = encontrada(%{tamano: :grande, nombre: nil, zona: "zona_sur"})

      assert {:ok, 60} = Coincidencias.puntaje(p, e)
      assert [%{puntaje: 60}] = Coincidencias.buscar(indexar([p, e]))
    end

    test "excluye una pareja por debajo del umbral" do
      # color 40 + tamaño 15 = 55
      e = encontrada(%{zona: "zona_sur", nombre: nil, caracteristicas: []})

      assert {:ok, 55} = Coincidencias.puntaje(perdida(), e)
      assert [] = Coincidencias.buscar(indexar([perdida(), e]))
    end

    test "color y zona iguales bastan para superar el umbral" do
      e = encontrada(%{tamano: :grande, nombre: nil, caracteristicas: []})

      # color 40 + zona 30 + tamaño adyacente 7 = 77
      assert [%{puntaje: 77}] = Coincidencias.buscar(indexar([perdida(), e]))
    end

    test "ignora especies distintas y reportes del mismo tipo" do
      reportes =
        indexar([
          perdida(),
          encontrada(%{id: "MA002", especie: "gato"}),
          perdida(%{id: "MA003"})
        ])

      assert [] = Coincidencias.buscar(reportes)
    end

    test "solo considera reportes activos" do
      for estado <- [:posible_coincidencia, :resuelta] do
        assert [] = Coincidencias.buscar(indexar([perdida(), encontrada(%{estado: estado})]))
        assert [] = Coincidencias.buscar(indexar([perdida(%{estado: estado}), encontrada()]))
      end
    end

    test "ordena por puntaje descendente y desempata por identificador" do
      reportes =
        indexar([
          perdida(),
          encontrada(%{id: "MA007"}),
          encontrada(%{id: "MA006", tamano: :grande, nombre: nil, caracteristicas: []}),
          encontrada(%{id: "MA002"})
        ])

      resultado =
        Enum.map(Coincidencias.buscar(reportes), &{&1.perdida, &1.encontrada, &1.puntaje})

      assert resultado == [
               {"MA001", "MA002", 130},
               {"MA001", "MA007", 130},
               {"MA001", "MA006", 77}
             ]
    end

    test "compara cada perdida con cada encontrada" do
      reportes = indexar([perdida(), perdida(%{id: "MA003"}), encontrada()])

      resultado = Enum.map(Coincidencias.buscar(reportes), &{&1.perdida, &1.encontrada})

      assert resultado == [{"MA001", "MA002"}, {"MA003", "MA002"}]
    end

    test "funciona con reportes creados mediante Reportes.registrar/2" do
      base = %{
        especie: "Perro",
        color: "Negra",
        tamano: "mediano",
        zona: "zona_norte",
        caracteristicas: ["Collar rojo", "oreja caida"]
      }

      {:ok, reportes, _} =
        Reportes.registrar(
          %{},
          Map.merge(base, %{id: "MA001", tipo: "perdida", nombre: "Luna", contacto: "3001234567"})
        )

      {:ok, reportes, _} =
        Reportes.registrar(
          reportes,
          Map.merge(base, %{
            id: "MA002",
            tipo: "found",
            nombre: "desconocido",
            contacto: "3009999999"
          })
        )

      assert [%{perdida: "MA001", encontrada: "MA002", puntaje: 105}] =
               Coincidencias.buscar(reportes)
    end
  end
end
