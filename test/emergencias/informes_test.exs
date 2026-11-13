defmodule Emergencias.InformesTest do
  use ExUnit.Case, async: true

  alias Emergencias.Familiares.{Mensaje, Persona}
  alias Emergencias.Informes
  alias Emergencias.Mascotas.Mascota
  alias Emergencias.Recursos.{Albergue, Necesidad, Recurso}
  alias Emergencias.Zonas.{Punto, Sector, Zona}

  defp datos do
    %{
      zonas: [
        %Zona{
          codigo: "Z1",
          nombre: "Centro",
          nivel: :critico,
          afectados: 100,
          sectores: [
            %Sector{
              codigo: "S1",
              nombre: "Sector 1",
              afectados: 50,
              puntos: [%Punto{codigo: "P1", nombre: "Punto A", afectados: 10}]
            }
          ]
        },
        %Zona{codigo: "Z2", nombre: "Norte", nivel: :bajo, afectados: 5}
      ],
      albergues: [
        %Albergue{
          codigo: "A1",
          nombre: "Albergue Uno",
          zona: "Z1",
          capacidad_maxima: 100,
          ocupacion: ["D1", "D2"]
        },
        %Albergue{
          codigo: "A2",
          nombre: "Albergue Dos",
          zona: "Z2",
          capacidad_maxima: 50,
          ocupacion: []
        }
      ],
      recursos: [
        %Recurso{
          codigo: "R1",
          nombre: "Agua",
          categoria: "agua",
          cantidad: 20,
          unidad: "litros",
          ubicacion: "A1"
        },
        %Recurso{
          codigo: "R2",
          nombre: "Arroz",
          categoria: "alimento",
          cantidad: 5,
          unidad: "kg",
          ubicacion: "Z1"
        },
        %Recurso{
          codigo: "R3",
          nombre: "Mantas",
          categoria: "refugio",
          cantidad: 40,
          unidad: "unidades",
          ubicacion: "A2"
        }
      ],
      necesidades: [
        %Necesidad{
          id: "N1",
          tipo: "agua",
          descripcion: "Agua potable",
          cantidad: 30,
          zona: "Z1",
          prioridad: 1,
          responsable: "laura",
          estado: :pendiente
        },
        %Necesidad{
          id: "N2",
          tipo: "agua",
          descripcion: "Agua para cocinar",
          cantidad: 25,
          zona: "Z1",
          prioridad: 2,
          responsable: "laura",
          estado: :atendida
        },
        %Necesidad{
          id: "N3",
          tipo: "mantas",
          descripcion: "Mantas térmicas",
          cantidad: 10,
          zona: "Z2",
          prioridad: 3,
          responsable: "pedro",
          estado: :pendiente
        }
      ],
      personas: [
        %Persona{
          id: "P1",
          nombre: "Andres",
          documento: "DOC111",
          edad: 30,
          zona: "Z1",
          estado: :localizada
        },
        %Persona{
          id: "P2",
          nombre: "Marta",
          documento: "DOC222",
          edad: 41,
          zona: "Z2",
          estado: :reportada
        }
      ],
      mensajes: [
        %Mensaje{
          id: "M1",
          fecha: ~U[2026-11-12 10:00:00Z],
          remitente: "ana",
          destinatario: "andres",
          contenido: "hola",
          estado: :pendiente
        },
        %Mensaje{
          id: "M2",
          fecha: ~U[2026-11-12 11:00:00Z],
          remitente: "ana",
          destinatario: "andres",
          contenido: "bien",
          estado: :entregado
        }
      ],
      mascotas: [
        %Mascota{
          id: "K1",
          tipo: :perdida,
          especie: "perro",
          color: "negro",
          tamano: :mediano,
          zona: "Z1",
          contacto: "300",
          estado: :posible_coincidencia
        },
        %Mascota{
          id: "K2",
          tipo: :encontrada,
          especie: "perro",
          color: "negro",
          tamano: :mediano,
          zona: "Z1",
          contacto: "301",
          estado: :posible_coincidencia
        },
        %Mascota{
          id: "K3",
          tipo: :perdida,
          especie: "gato",
          color: "gris",
          tamano: :pequeno,
          zona: "Z2",
          contacto: "302",
          estado: :resuelta
        }
      ]
    }
  end

  describe "resumen_global/1" do
    test "calcula las estadísticas de cada sección" do
      r = Informes.resumen_global(datos())

      assert r.zonas == %{total: 2, afectados: 100 + 50 + 10 + 5}
      assert %{total: 2, capacidad: 150, ocupadas: 2, mas_ocupados: [%Albergue{codigo: "A1"}]} =
               r.albergues

      assert r.necesidades == %{total: 3, pendientes: 2, atendidas: 1}
      assert r.mensajes == %{total: 2, pendientes: 1, entregados: 1}
      assert r.personas.total == 2
      assert [%Persona{nombre: "Andres"}] = r.personas.localizadas
      assert r.mascotas == %{total: 3, perdidas: 2, encontradas: 1, posibles: 2, resueltas: 1}
    end

    test "los albergues más ocupados van por porcentaje, sin vacíos y máximo tres" do
      albergue = fn codigo, capacidad, ocupados ->
        %Albergue{
          codigo: codigo,
          nombre: "Albergue #{codigo}",
          zona: "Z1",
          capacidad_maxima: capacidad,
          ocupacion: Enum.map(1..ocupados//1, &"#{codigo}-#{&1}")
        }
      end

      albergues = [
        albergue.("B", 10, 1),
        albergue.("C", 100, 5),
        albergue.("D", 10, 9),
        albergue.("E", 10, 0),
        albergue.("F", 10, 2)
      ]

      r = Informes.resumen_global(%{datos() | albergues: albergues})

      assert Enum.map(r.albergues.mas_ocupados, & &1.codigo) == ["D", "F", "B"]
    end

    test "sin ningún albergue ocupado no se muestra el bloque" do
      albergues = [%Albergue{codigo: "A", nombre: "A", zona: "Z1", capacidad_maxima: 10}]

      texto =
        %{datos() | albergues: albergues}
        |> Informes.resumen_global()
        |> Informes.formatear_global()

      assert texto =~ "Albergues: 1 (ocupación 0/10)"
      refute texto =~ "más ocupados"
    end

    test "ordena los recursos de menor a mayor cantidad restante" do
      r = Informes.resumen_global(datos())
      assert Enum.map(r.recursos, & &1.codigo) == ["R2", "R1", "R3"]
    end
  end

  describe "formatear_global/1" do
    test "muestra recursos restantes, pendientes, localizadas, mensajes y mascotas" do
      texto = datos() |> Informes.resumen_global() |> Informes.formatear_global()

      assert texto =~ "RESUMEN GLOBAL"
      assert texto =~ "Agua (R1): 20 litros en A1"
      assert texto =~ "2 pendientes, 1 atendidas"
      assert texto =~ "Albergues más ocupados:"
      assert texto =~ "Albergue Uno (A1): 2/100 (2.0%)"
      assert texto =~ "Personas localizadas: 1"
      assert texto =~ "Andres (doc. DOC111"
      assert texto =~ "Mensajes: 2 (1 pendientes, 1 entregados)"
      assert texto =~ "3 reportes (2 perdidas, 1 encontradas)"
    end

    test "una fuente caída aparece como no disponible sin afectar al resto" do
      datos = %{datos() | recursos: :no_disponible, mascotas: :no_disponible}
      texto = datos |> Informes.resumen_global() |> Informes.formatear_global()

      assert texto =~ "Recursos restantes: no disponible"
      assert texto =~ "Mascotas: no disponible"
      assert texto =~ "Zonas: 2"
      assert texto =~ "Mensajes: 2"
    end

    test "sin datos no falla" do
      vacio = %{
        zonas: [],
        albergues: [],
        recursos: [],
        necesidades: [],
        personas: [],
        mensajes: [],
        mascotas: []
      }

      texto = vacio |> Informes.resumen_global() |> Informes.formatear_global()

      assert texto =~ "ninguno registrado"
      assert texto =~ "Personas localizadas: ninguna"
    end
  end

  describe "asociados_a_zona/2" do
    test "asocia cada entidad a la zona por su campo de zona o, los recursos, por su albergue" do
      a = Informes.asociados_a_zona("Z1", datos())

      assert Enum.map(a.albergues, & &1.codigo) == ["A1"]
      assert Enum.map(a.necesidades, & &1.id) == ["N1", "N2"]
      assert a.recursos |> Enum.map(& &1.codigo) |> Enum.sort() == ["R1", "R2"]
      assert Enum.map(a.personas, & &1.id) == ["P1"]
      assert a.mascotas |> Enum.map(& &1.id) |> Enum.sort() == ["K1", "K2"]
    end

    test "una zona sin nada asociado devuelve listas vacías" do
      a = Informes.asociados_a_zona("ZX", datos())
      assert a == %{albergues: [], necesidades: [], recursos: [], personas: [], mascotas: []}
    end

    test "si no se leen los albergues, solo los recursos de albergue se pierden" do
      a = Informes.asociados_a_zona("Z1", %{datos() | albergues: :no_disponible})
      assert a.albergues == :no_disponible
      assert Enum.map(a.necesidades, & &1.id) == ["N1", "N2"]
      assert Enum.map(a.recursos, & &1.codigo) == ["R2"]
    end
  end

  describe "formatear_zona/1" do
    test "lista cada bloque con su cantidad" do
      texto = "Z1" |> Informes.asociados_a_zona(datos()) |> Informes.formatear_zona()

      assert texto =~ "Albergues (1):"
      assert texto =~ "A1 Albergue Uno: 2/100 ocupados"
      assert texto =~ "Necesidades (2):"
      assert texto =~ "[N1] 30 de agua (Agua potable), prioridad 1 (pendiente)"
      assert texto =~ "Recursos (2):"
      assert texto =~ "Personas (1):"
      assert texto =~ "Mascotas (2):"
    end

    test "indica los bloques vacíos" do
      texto = "ZX" |> Informes.asociados_a_zona(datos()) |> Informes.formatear_zona()
      assert texto =~ "Albergues: sin registros"
      assert texto =~ "Mascotas: sin registros"
    end
  end
end
