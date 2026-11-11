defmodule Emergencias.Familiares.PersonasTest do
  use ExUnit.Case, async: true

  alias Emergencias.Familiares.Personas

  doctest Emergencias.Familiares.Personas

  @t0 ~U[2026-11-10 08:00:00Z]
  @t1 ~U[2026-11-10 09:30:00Z]
  @t2 ~U[2026-11-10 11:00:00Z]

  defp atributos(extra \\ %{}) do
    Map.merge(
      %{
        id: "PE001",
        nombre: "Ana Pérez",
        documento: "1094567890",
        edad: 34,
        zona: "zona_norte"
      },
      extra
    )
  end

  # PE001 Ana (norte, reportada), PE002 Luis (sur, reportada), PE003 María (norte, sin_informacion)
  defp personas_base do
    {:ok, p1, _} = Personas.registrar(%{}, atributos(), @t0)

    {:ok, p2, _} =
      Personas.registrar(
        p1,
        atributos(%{id: "PE002", nombre: "Luis Gómez", documento: "52123456", zona: "zona_sur"}),
        @t0
      )

    {:ok, p3, _} =
      Personas.registrar(
        p2,
        atributos(%{
          id: "PE003",
          nombre: "María Ríos",
          documento: "AB123456",
          estado: :sin_informacion
        }),
        @t0
      )

    p3
  end

  defp ids({:ok, lista}), do: Enum.map(lista, & &1.id)

  describe "registrar/3 con datos válidos" do
    test "crea la persona reportada con su primer cambio en el historial" do
      assert {:ok, personas, persona} = Personas.registrar(%{}, atributos(), @t0)

      assert persona.id == "PE001"
      assert persona.nombre == "Ana Pérez"
      assert persona.documento == "1094567890"
      assert persona.edad == 34
      assert persona.estado == :reportada
      assert persona.historial == [%{estado: :reportada, fecha: @t0}]
      assert personas["PE001"] == persona
    end

    test "permite iniciar como sin_informacion" do
      assert {:ok, _, %{estado: :sin_informacion, historial: [%{estado: :sin_informacion}]}} =
               Personas.registrar(%{}, atributos(%{estado: "sin_informacion"}), @t0)
    end

    test "guarda el documento en mayúsculas y sin espacios" do
      assert {:ok, _, %{documento: "AB123456"}} =
               Personas.registrar(%{}, atributos(%{documento: " ab123456 "}), @t0)
    end

    test "acepta un documento y una edad numéricos o en texto" do
      assert {:ok, _, %{documento: "1094567890", edad: 12}} =
               Personas.registrar(%{}, atributos(%{documento: 1_094_567_890, edad: "12"}), @t0)
    end

    test "acepta las edades límite 0 y 120" do
      assert {:ok, _, %{edad: 0}} = Personas.registrar(%{}, atributos(%{edad: 0}), @t0)
      assert {:ok, _, %{edad: 120}} = Personas.registrar(%{}, atributos(%{edad: 120}), @t0)
    end

    test "acepta documentos de 5 y de 15 caracteres" do
      assert {:ok, _, _} = Personas.registrar(%{}, atributos(%{documento: "12345"}), @t0)

      assert {:ok, _, _} =
               Personas.registrar(%{}, atributos(%{documento: "123456789012345"}), @t0)
    end

    test "usa la hora actual cuando no se indica la fecha" do
      assert {:ok, _, %{historial: [%{fecha: %DateTime{}}]}} =
               Personas.registrar(%{}, atributos())
    end
  end

  describe "registrar/3 con datos inválidos" do
    test "rechaza un identificador o un documento repetido" do
      {:ok, personas, _} = Personas.registrar(%{}, atributos(), @t0)

      assert {:error, :id_existente} = Personas.registrar(personas, atributos(), @t0)

      assert {:error, :documento_existente} =
               Personas.registrar(personas, atributos(%{id: "PE002"}), @t0)

      assert {:error, :documento_existente} =
               Personas.registrar(
                 personas,
                 atributos(%{id: "PE002", documento: "1094567890 "}),
                 @t0
               )
    end

    test "rechaza campos de texto vacíos o que no son texto" do
      assert {:error, :id_invalido} = Personas.registrar(%{}, atributos(%{id: ""}), @t0)
      assert {:error, :id_invalido} = Personas.registrar(%{}, atributos(%{id: 1}), @t0)
      assert {:error, :nombre_invalido} = Personas.registrar(%{}, atributos(%{nombre: "  "}), @t0)
      assert {:error, :zona_invalida} = Personas.registrar(%{}, atributos(%{zona: nil}), @t0)
    end

    test "rechaza documentos fuera de formato" do
      for documento <- ["1234", "1234567890123456", "12 345 678", "12-345-678", "", nil, -5] do
        assert {:error, :documento_invalido} =
                 Personas.registrar(%{}, atributos(%{documento: documento}), @t0)
      end
    end

    test "rechaza edades fuera de rango o que no son números" do
      for edad <- [-1, 121, "abc", "12.5", "", nil, 3.5] do
        assert {:error, :edad_invalida} =
                 Personas.registrar(%{}, atributos(%{edad: edad}), @t0)
      end
    end

    test "rechaza estados iniciales inexistentes o que suponen avance" do
      assert {:error, :estado_invalido} =
               Personas.registrar(%{}, atributos(%{estado: "perdida"}), @t0)

      assert {:error, :estado_inicial_invalido} =
               Personas.registrar(%{}, atributos(%{estado: :reunificada}), @t0)

      assert {:error, :estado_inicial_invalido} =
               Personas.registrar(%{}, atributos(%{estado: "en_albergue"}), @t0)
    end

    test "un registro rechazado no modifica la colección" do
      personas = personas_base()

      assert {:error, :edad_invalida} =
               Personas.registrar(
                 personas,
                 atributos(%{id: "PE009", documento: "77777", edad: -1}),
                 @t0
               )

      assert {:error, :persona_no_encontrada} = Personas.obtener(personas, "PE009")
    end
  end

  describe "siguiente_id/1" do
    test "continúa la numeración" do
      assert Personas.siguiente_id(personas_base()) == "PE004"
    end

    test "evita identificadores ya ocupados" do
      assert Personas.siguiente_id(%{"PE002" => :cualquiera}) == "PE003"
    end
  end

  describe "obtener/2" do
    test "retorna la persona o un error si no existe" do
      assert {:ok, %{id: "PE001"}} = Personas.obtener(personas_base(), "PE001")
      assert {:error, :persona_no_encontrada} = Personas.obtener(personas_base(), "PE999")
      assert {:error, :persona_no_encontrada} = Personas.obtener(personas_base(), nil)
    end
  end

  describe "consultar/2" do
    test "sin filtros retorna todo ordenado por identificador" do
      assert ids(Personas.consultar(personas_base())) == ["PE001", "PE002", "PE003"]
    end

    test "busca por fragmento de nombre sin distinguir mayúsculas ni tildes" do
      assert ids(Personas.consultar(personas_base(), nombre: "perez")) == ["PE001"]
      assert ids(Personas.consultar(personas_base(), nombre: "MARIA")) == ["PE003"]
      assert ids(Personas.consultar(personas_base(), nombre: "í")) == ["PE002", "PE003"]
      assert ids(Personas.consultar(personas_base(), nombre: "a")) == ["PE001", "PE003"]
      assert ids(Personas.consultar(personas_base(), nombre: " luis ")) == ["PE002"]
    end

    test "busca por documento exacto, sin distinguir mayúsculas" do
      assert ids(Personas.consultar(personas_base(), documento: "ab123456")) == ["PE003"]
      assert ids(Personas.consultar(personas_base(), documento: "123")) == []
    end

    test "busca por zona y por estado" do
      assert ids(Personas.consultar(personas_base(), zona: "zona_norte")) == ["PE001", "PE003"]
      assert ids(Personas.consultar(personas_base(), estado: "sin_informacion")) == ["PE003"]
      assert ids(Personas.consultar(personas_base(), estado: :reportada)) == ["PE001", "PE002"]
    end

    test "combina varios filtros" do
      assert ids(Personas.consultar(personas_base(), zona: "zona_norte", estado: :reportada)) ==
               ["PE001"]
    end

    test "sin coincidencias o sin personas retorna lista vacía" do
      assert {:ok, []} = Personas.consultar(personas_base(), nombre: "zzz")
      assert {:ok, []} = Personas.consultar(%{})
    end

    test "rechaza filtros desconocidos o con valores inválidos" do
      assert {:error, {:filtro_invalido, :edad}} = Personas.consultar(personas_base(), edad: 3)

      assert {:error, {:filtro_invalido, :nombre}} =
               Personas.consultar(personas_base(), nombre: "  ")

      assert {:error, {:filtro_invalido, :nombre}} =
               Personas.consultar(personas_base(), nombre: 5)

      assert {:error, {:filtro_invalido, :zona}} = Personas.consultar(personas_base(), zona: nil)

      assert {:error, {:filtro_invalido, :documento}} =
               Personas.consultar(personas_base(), documento: 5)

      assert {:error, :estado_invalido} = Personas.consultar(personas_base(), estado: "rara")

      assert {:error, {:filtro_invalido, :suelto}} =
               Personas.consultar(personas_base(), [:suelto])
    end
  end

  describe "transicion_valida?/2" do
    test "permite los cambios del proceso" do
      assert Personas.transicion_valida?(:sin_informacion, :reportada)
      assert Personas.transicion_valida?(:sin_informacion, :localizada)
      assert Personas.transicion_valida?(:reportada, :localizada)
      assert Personas.transicion_valida?(:localizada, :trasladada)
      assert Personas.transicion_valida?(:localizada, :en_albergue)
      assert Personas.transicion_valida?(:localizada, :reunificada)
      assert Personas.transicion_valida?(:trasladada, :en_albergue)
      assert Personas.transicion_valida?(:en_albergue, :trasladada)
      assert Personas.transicion_valida?(:en_albergue, :reunificada)
    end

    test "rechaza retrocesos, saltos y repetir un estado" do
      refute Personas.transicion_valida?(:reportada, :sin_informacion)
      refute Personas.transicion_valida?(:reportada, :en_albergue)
      refute Personas.transicion_valida?(:localizada, :reportada)
      refute Personas.transicion_valida?(:localizada, :localizada)
    end

    test "no permite salir de reunificada ni usar estados inexistentes" do
      for destino <- Emergencias.Familiares.Persona.estados() do
        refute Personas.transicion_valida?(:reunificada, destino)
      end

      refute Personas.transicion_valida?(:inventado, :localizada)
      refute Personas.transicion_valida?(:localizada, :inventado)
    end
  end

  describe "cambiar_estado/4" do
    test "cambia el estado y lo anota en el historial en orden cronológico" do
      {:ok, personas, _} = Personas.cambiar_estado(personas_base(), "PE001", :localizada, @t1)
      {:ok, personas, persona} = Personas.cambiar_estado(personas, "PE001", "en_albergue", @t2)

      assert persona.estado == :en_albergue

      assert persona.historial == [
               %{estado: :reportada, fecha: @t0},
               %{estado: :localizada, fecha: @t1},
               %{estado: :en_albergue, fecha: @t2}
             ]

      assert personas["PE001"] == persona
      assert personas["PE002"].estado == :reportada
    end

    test "recorre el proceso completo hasta la reunificación" do
      {:ok, personas, _} = Personas.cambiar_estado(personas_base(), "PE003", :reportada, @t1)
      {:ok, personas, _} = Personas.cambiar_estado(personas, "PE003", :localizada, @t1)
      {:ok, personas, _} = Personas.cambiar_estado(personas, "PE003", :trasladada, @t1)
      {:ok, personas, _} = Personas.cambiar_estado(personas, "PE003", :en_albergue, @t1)
      {:ok, _, persona} = Personas.cambiar_estado(personas, "PE003", :reunificada, @t2)

      assert Enum.map(persona.historial, & &1.estado) ==
               [
                 :sin_informacion,
                 :reportada,
                 :localizada,
                 :trasladada,
                 :en_albergue,
                 :reunificada
               ]
    end

    test "rechaza cambios no permitidos sin modificar el historial" do
      personas = personas_base()

      assert {:error, {:transicion_invalida, :reportada, :en_albergue}} =
               Personas.cambiar_estado(personas, "PE001", :en_albergue, @t1)

      assert {:error, {:transicion_invalida, :reportada, :reportada}} =
               Personas.cambiar_estado(personas, "PE001", :reportada, @t1)

      assert length(personas["PE001"].historial) == 1
    end

    test "no permite cerrar dos veces un caso" do
      {:ok, personas, _} = Personas.cambiar_estado(personas_base(), "PE001", :localizada, @t1)
      {:ok, personas, _} = Personas.cambiar_estado(personas, "PE001", :reunificada, @t2)

      assert {:error, :persona_reunificada} =
               Personas.cambiar_estado(personas, "PE001", :reunificada, @t2)

      assert {:error, :persona_reunificada} =
               Personas.cambiar_estado(personas, "PE001", :localizada, @t2)
    end

    test "rechaza personas inexistentes y estados inválidos" do
      assert {:error, :persona_no_encontrada} =
               Personas.cambiar_estado(personas_base(), "PE999", :localizada, @t1)

      assert {:error, :estado_invalido} =
               Personas.cambiar_estado(personas_base(), "PE001", "rara", @t1)

      assert {:error, :estado_invalido} =
               Personas.cambiar_estado(personas_base(), "PE001", nil, @t1)

      assert {:error, :estado_invalido} =
               Personas.cambiar_estado(personas_base(), "PE001", 5, @t1)
    end

    test "usa la hora actual cuando no se indica la fecha" do
      assert {:ok, _, %{historial: [_, %{estado: :localizada, fecha: %DateTime{}}]}} =
               Personas.cambiar_estado(personas_base(), "PE001", :localizada)
    end
  end

  describe "a_registro/1 y de_registro/1" do
    test "recuperan la misma persona con su historial tras pasar por JSON" do
      {:ok, personas, _} = Personas.cambiar_estado(personas_base(), "PE001", :localizada, @t1)
      original = personas["PE001"]

      {:ok, leido} = original |> Personas.a_registro() |> JSON.encode!() |> JSON.decode()

      assert {:ok, ^original} = Personas.de_registro(leido)
    end

    test "acepta un registro mínimo y aplica los valores por defecto" do
      registro = %{
        "id" => "PE010",
        "nombre" => "Sara",
        "documento" => "99999",
        "edad" => 8,
        "zona" => "zona_sur"
      }

      assert {:ok, persona} = Personas.de_registro(registro)
      assert persona.estado == :reportada
      assert persona.historial == []
    end

    test "rechaza registros incompletos o que no son un mapa" do
      assert {:error, :registro_invalido} = Personas.de_registro(%{"id" => "PE001"})
      assert {:error, :registro_invalido} = Personas.de_registro("texto")
      assert {:error, :registro_invalido} = Personas.de_registro(nil)
    end

    test "rechaza valores inválidos" do
      registro = Personas.a_registro(personas_base()["PE001"])

      assert {:error, :registro_invalido} = Personas.de_registro(%{registro | "id" => 1})
      assert {:error, :edad_invalida} = Personas.de_registro(%{registro | "edad" => -3})
      assert {:error, :edad_invalida} = Personas.de_registro(%{registro | "edad" => nil})
      assert {:error, :estado_invalido} = Personas.de_registro(%{registro | "estado" => "rara"})
    end

    test "rechaza historiales mal formados" do
      registro = Personas.a_registro(personas_base()["PE001"])

      assert {:error, :historial_invalido} =
               Personas.de_registro(%{registro | "historial" => "no lista"})

      assert {:error, :historial_invalido} =
               Personas.de_registro(%{registro | "historial" => [%{"estado" => "reportada"}]})

      assert {:error, :historial_invalido} =
               Personas.de_registro(%{registro | "historial" => [1]})

      assert {:error, :fecha_invalida} =
               Personas.de_registro(%{
                 registro
                 | "historial" => [%{"estado" => "reportada", "fecha" => "ayer"}]
               })

      assert {:error, :estado_invalido} =
               Personas.de_registro(%{
                 registro
                 | "historial" => [%{"estado" => "rara", "fecha" => "2026-11-10T08:00:00Z"}]
               })
    end
  end
end
