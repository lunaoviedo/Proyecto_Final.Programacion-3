defmodule Emergencias.Familiares.ServidorFamiliaresTest do
  use ExUnit.Case, async: true

  alias Emergencias.Familiares.ServidorFamiliares
  alias Emergencias.Persistencia

  setup do
    sufijo = System.unique_integer([:positive])
    entidades = %{personas: :"personas_prueba_#{sufijo}", mensajes: :"mensajes_prueba_#{sufijo}"}
    nombre = :"servidor_familiares_prueba_#{sufijo}"

    on_exit(fn -> limpiar(entidades) end)

    start_supervised!(
      {ServidorFamiliares,
       name: nombre, entidad_personas: entidades.personas, entidad_mensajes: entidades.mensajes}
    )

    %{servidor: nombre, entidades: entidades}
  end

  defp limpiar(entidades) do
    for {_clave, entidad} <- entidades do
      File.rm_rf(Persistencia.ruta_archivo(entidad))
      File.rm_rf(Persistencia.ruta_archivo(entidad) <> ".tmp")
    end
  end

  defp persona(extra \\ %{}) do
    Map.merge(
      %{
        nombre: "Ana Gómez",
        documento:
          "DOC" <>
            String.pad_leading(Integer.to_string(System.unique_integer([:positive])), 8, "0"),
        edad: 34,
        zona: "zona_norte"
      },
      extra
    )
  end

  defp mensaje(extra \\ %{}) do
    Map.merge(
      %{remitente: "luis", destinatario: "ana", contenido: "Estoy bien, ¿y ustedes?"},
      extra
    )
  end

  defp ids({:ok, lista}), do: Enum.map(lista, & &1.id)

  defp en_paralelo(cantidad, funcion) do
    1..cantidad
    |> Task.async_stream(funcion, max_concurrency: cantidad, timeout: 15_000)
    |> Enum.map(fn {:ok, resultado} -> resultado end)
  end

  describe "registrar_persona/2" do
    test "genera identificadores consecutivos cuando no se indican", %{servidor: s} do
      assert {:ok, %{id: "PE001", estado: :reportada}} =
               ServidorFamiliares.registrar_persona(persona(), s)

      assert {:ok, %{id: "PE002"}} = ServidorFamiliares.registrar_persona(persona(), s)
    end

    test "respeta un identificador indicado y no lo repite", %{servidor: s} do
      assert {:ok, %{id: "PE050"}} =
               ServidorFamiliares.registrar_persona(persona(%{id: "PE050"}), s)

      assert {:error, :id_existente} =
               ServidorFamiliares.registrar_persona(persona(%{id: "PE050"}), s)
    end

    test "no admite dos personas con el mismo documento", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(%{documento: "abc12345"}), s)

      assert {:error, :documento_existente} =
               ServidorFamiliares.registrar_persona(persona(%{documento: "ABC12345"}), s)
    end

    test "rechaza datos inválidos sin modificar el estado", %{servidor: s} do
      assert {:error, :nombre_invalido} =
               ServidorFamiliares.registrar_persona(persona(%{nombre: "  "}), s)

      assert {:error, :documento_invalido} =
               ServidorFamiliares.registrar_persona(persona(%{documento: "12"}), s)

      assert {:error, :edad_invalida} =
               ServidorFamiliares.registrar_persona(persona(%{edad: 121}), s)

      assert {:error, :estado_inicial_invalido} =
               ServidorFamiliares.registrar_persona(persona(%{estado: :reunificada}), s)

      assert {:error, :atributos_invalidos} = ServidorFamiliares.registrar_persona("texto", s)
      assert {:error, :atributos_invalidos} = ServidorFamiliares.registrar_persona(nil, s)

      assert {:ok, []} = ServidorFamiliares.consultar_personas([], s)
    end

    test "acepta las edades límite 0 y 120", %{servidor: s} do
      assert {:ok, %{edad: 0}} = ServidorFamiliares.registrar_persona(persona(%{edad: 0}), s)
      assert {:ok, %{edad: 120}} = ServidorFamiliares.registrar_persona(persona(%{edad: 120}), s)
    end

    test "guarda cada persona en el archivo", %{servidor: s, entidades: entidades} do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)

      assert {:ok, [%{"id" => "PE001"}, %{"id" => "PE002"}]} =
               Persistencia.cargar(entidades.personas)
    end
  end

  describe "obtener_persona/2 y consultar_personas/2" do
    test "obtiene una persona existente y falla con una inexistente", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)

      assert {:ok, %{id: "PE001"}} = ServidorFamiliares.obtener_persona("PE001", s)
      assert {:error, :persona_no_encontrada} = ServidorFamiliares.obtener_persona("PE999", s)
      assert {:error, :persona_no_encontrada} = ServidorFamiliares.obtener_persona(nil, s)
    end

    test "consulta por nombre, documento, zona y estado", %{servidor: s} do
      {:ok, _} =
        ServidorFamiliares.registrar_persona(persona(%{documento: "DOC11111"}), s)

      {:ok, _} =
        ServidorFamiliares.registrar_persona(
          persona(%{nombre: "Pedro Ríos", documento: "DOC22222", zona: "zona_sur"}),
          s
        )

      {:ok, _} = ServidorFamiliares.cambiar_estado("PE002", :localizada, s)

      assert ids(ServidorFamiliares.consultar_personas([nombre: "gomez"], s)) == ["PE001"]
      assert ids(ServidorFamiliares.consultar_personas([documento: "doc22222"], s)) == ["PE002"]
      assert ids(ServidorFamiliares.consultar_personas([zona: "zona_sur"], s)) == ["PE002"]
      assert ids(ServidorFamiliares.consultar_personas([estado: "localizada"], s)) == ["PE002"]
      assert ids(ServidorFamiliares.consultar_personas([], s)) == ["PE001", "PE002"]
    end

    test "rechaza filtros inválidos", %{servidor: s} do
      assert {:error, {:filtro_invalido, :color}} =
               ServidorFamiliares.consultar_personas([color: "rojo"], s)

      assert {:error, :estado_invalido} =
               ServidorFamiliares.consultar_personas([estado: "volando"], s)

      assert {:error, :filtros_invalidos} = ServidorFamiliares.consultar_personas(:todos, s)
    end

    test "un filtro sin coincidencias retorna una lista vacía", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)

      assert {:ok, []} = ServidorFamiliares.consultar_personas([zona: "zona_inexistente"], s)
    end
  end

  describe "cambiar_estado/3" do
    test "avanza por las transiciones válidas y anota el historial", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)

      assert {:ok, %{estado: :localizada}} =
               ServidorFamiliares.cambiar_estado("PE001", :localizada, s)

      assert {:ok, %{estado: :en_albergue}} =
               ServidorFamiliares.cambiar_estado("PE001", "en_albergue", s)

      assert {:ok, persona} = ServidorFamiliares.obtener_persona("PE001", s)
      assert Enum.map(persona.historial, & &1.estado) == [:reportada, :localizada, :en_albergue]
    end

    test "rechaza una transición no permitida", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)

      assert {:error, {:transicion_invalida, :reportada, :reunificada}} =
               ServidorFamiliares.cambiar_estado("PE001", :reunificada, s)

      assert {:ok, %{estado: :reportada}} = ServidorFamiliares.obtener_persona("PE001", s)
    end

    test "rechaza estados e identificadores inválidos", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)

      assert {:error, :estado_invalido} = ServidorFamiliares.cambiar_estado("PE001", "volando", s)
      assert {:error, :estado_invalido} = ServidorFamiliares.cambiar_estado("PE001", nil, s)

      assert {:error, :persona_no_encontrada} =
               ServidorFamiliares.cambiar_estado("PE999", :localizada, s)
    end

    test "no se puede cerrar dos veces el caso de una persona", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)
      {:ok, _} = ServidorFamiliares.cambiar_estado("PE001", :localizada, s)
      {:ok, _} = ServidorFamiliares.cambiar_estado("PE001", :reunificada, s)

      assert {:error, :persona_reunificada} =
               ServidorFamiliares.cambiar_estado("PE001", :reunificada, s)

      assert {:error, :persona_reunificada} =
               ServidorFamiliares.cambiar_estado("PE001", :localizada, s)
    end

    test "guarda el cambio en el archivo", %{servidor: s, entidades: entidades} do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)
      {:ok, _} = ServidorFamiliares.cambiar_estado("PE001", :localizada, s)

      assert {:ok, [%{"estado" => "localizada", "historial" => historial}]} =
               Persistencia.cargar(entidades.personas)

      assert length(historial) == 2
    end
  end

  describe "enviar_mensaje/2" do
    test "genera identificadores consecutivos y nace pendiente", %{servidor: s} do
      assert {:ok, %{id: "ME001", estado: :pendiente}} =
               ServidorFamiliares.enviar_mensaje(mensaje(), s)

      assert {:ok, %{id: "ME002"}} = ServidorFamiliares.enviar_mensaje(mensaje(), s)
    end

    test "respeta un identificador indicado y no lo repite", %{servidor: s} do
      assert {:ok, %{id: "ME050"}} = ServidorFamiliares.enviar_mensaje(mensaje(%{id: "ME050"}), s)

      assert {:error, :id_existente} =
               ServidorFamiliares.enviar_mensaje(mensaje(%{id: "ME050"}), s)
    end

    test "rechaza datos inválidos sin modificar el estado", %{servidor: s} do
      assert {:error, :remitente_invalido} =
               ServidorFamiliares.enviar_mensaje(mensaje(%{remitente: ""}), s)

      assert {:error, :contenido_invalido} =
               ServidorFamiliares.enviar_mensaje(mensaje(%{contenido: "   "}), s)

      assert {:error, :destinatario_es_remitente} =
               ServidorFamiliares.enviar_mensaje(mensaje(%{destinatario: "luis"}), s)

      assert {:error, :atributos_invalidos} = ServidorFamiliares.enviar_mensaje(nil, s)
      assert {:ok, []} = ServidorFamiliares.consultar_mensajes([], s)
    end

    test "acepta 500 caracteres y rechaza 501", %{servidor: s} do
      assert {:ok, _} =
               ServidorFamiliares.enviar_mensaje(
                 mensaje(%{contenido: String.duplicate("a", 500)}),
                 s
               )

      assert {:error, :contenido_demasiado_largo} =
               ServidorFamiliares.enviar_mensaje(
                 mensaje(%{contenido: String.duplicate("a", 501)}),
                 s
               )
    end

    test "guarda cada mensaje en el archivo", %{servidor: s, entidades: entidades} do
      {:ok, _} = ServidorFamiliares.enviar_mensaje(mensaje(), s)

      assert {:ok, [%{"id" => "ME001", "estado" => "pendiente"}]} =
               Persistencia.cargar(entidades.mensajes)
    end
  end

  describe "obtener_mensaje/2 y consultar_mensajes/2" do
    test "obtiene un mensaje existente y falla con uno inexistente", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.enviar_mensaje(mensaje(), s)

      assert {:ok, %{id: "ME001"}} = ServidorFamiliares.obtener_mensaje("ME001", s)
      assert {:error, :mensaje_no_encontrado} = ServidorFamiliares.obtener_mensaje("ME999", s)
      assert {:error, :mensaje_no_encontrado} = ServidorFamiliares.obtener_mensaje(nil, s)
    end

    test "consulta por remitente, destinatario, usuario y estado", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.enviar_mensaje(mensaje(), s)

      {:ok, _} =
        ServidorFamiliares.enviar_mensaje(mensaje(%{remitente: "ana", destinatario: "luis"}), s)

      {:ok, _} =
        ServidorFamiliares.enviar_mensaje(mensaje(%{remitente: "eva", destinatario: "pedro"}), s)

      {:ok, _} = ServidorFamiliares.marcar_entregado("ME001", s)

      assert ids(ServidorFamiliares.consultar_mensajes([remitente: "luis"], s)) == ["ME001"]
      assert ids(ServidorFamiliares.consultar_mensajes([destinatario: "luis"], s)) == ["ME002"]

      assert ids(ServidorFamiliares.consultar_mensajes([usuario: "luis"], s)) == [
               "ME001",
               "ME002"
             ]

      assert ids(ServidorFamiliares.consultar_mensajes([estado: "pendiente"], s)) == [
               "ME002",
               "ME003"
             ]
    end

    test "rechaza filtros inválidos", %{servidor: s} do
      assert {:error, {:filtro_invalido, :color}} =
               ServidorFamiliares.consultar_mensajes([color: "rojo"], s)

      assert {:error, {:filtro_invalido, :usuario}} =
               ServidorFamiliares.consultar_mensajes([usuario: ""], s)

      assert {:error, :filtros_invalidos} = ServidorFamiliares.consultar_mensajes("todos", s)
    end
  end

  describe "entrega de mensajes" do
    test "marcar_entregado/2 entrega un mensaje una sola vez", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.enviar_mensaje(mensaje(), s)

      assert {:ok, %{estado: :entregado}} = ServidorFamiliares.marcar_entregado("ME001", s)
      assert {:error, :mensaje_entregado} = ServidorFamiliares.marcar_entregado("ME001", s)
      assert {:error, :mensaje_no_encontrado} = ServidorFamiliares.marcar_entregado("ME999", s)
    end

    test "entregar_pendientes/2 entrega solo los pendientes del destinatario", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.enviar_mensaje(mensaje(), s)
      {:ok, _} = ServidorFamiliares.enviar_mensaje(mensaje(), s)
      {:ok, _} = ServidorFamiliares.enviar_mensaje(mensaje(%{destinatario: "eva"}), s)

      assert {:ok, entregados} = ServidorFamiliares.entregar_pendientes("ana", s)
      assert Enum.map(entregados, & &1.id) == ["ME001", "ME002"]
      assert Enum.all?(entregados, &(&1.estado == :entregado))

      assert ids(ServidorFamiliares.consultar_mensajes([estado: "pendiente"], s)) == ["ME003"]
    end

    test "entregar_pendientes/2 sin pendientes retorna una lista vacía", %{servidor: s} do
      assert {:ok, []} = ServidorFamiliares.entregar_pendientes("ana", s)
    end

    test "entregar_pendientes/2 rechaza un destinatario inválido", %{servidor: s} do
      assert {:error, :destinatario_invalido} = ServidorFamiliares.entregar_pendientes("", s)
      assert {:error, :destinatario_invalido} = ServidorFamiliares.entregar_pendientes(nil, s)
    end

    test "guarda la entrega en el archivo", %{servidor: s, entidades: entidades} do
      {:ok, _} = ServidorFamiliares.enviar_mensaje(mensaje(), s)
      {:ok, _} = ServidorFamiliares.entregar_pendientes("ana", s)

      assert {:ok, [%{"estado" => "entregado"}]} = Persistencia.cargar(entidades.mensajes)
    end
  end

  describe "persistencia" do
    test "recupera personas y mensajes al reiniciar el servidor", %{
      servidor: s,
      entidades: entidades
    } do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)
      {:ok, _} = ServidorFamiliares.cambiar_estado("PE001", :localizada, s)
      {:ok, _} = ServidorFamiliares.enviar_mensaje(mensaje(), s)

      stop_supervised!(ServidorFamiliares)

      start_supervised!(
        {ServidorFamiliares,
         name: s, entidad_personas: entidades.personas, entidad_mensajes: entidades.mensajes}
      )

      assert {:ok, %{estado: :localizada, historial: [_, _]}} =
               ServidorFamiliares.obtener_persona("PE001", s)

      assert {:ok, %{id: "ME001", estado: :pendiente}} =
               ServidorFamiliares.obtener_mensaje("ME001", s)

      assert {:ok, %{id: "PE002"}} = ServidorFamiliares.registrar_persona(persona(), s)
    end

    test "no inicia si un archivo contiene una línea que no es JSON" do
      Process.flag(:trap_exit, true)
      sufijo = System.unique_integer([:positive])
      personas = :"personas_corrupta_#{sufijo}"
      mensajes = :"mensajes_corrupta_#{sufijo}"
      ruta = Persistencia.ruta_archivo(personas)
      File.mkdir_p!(Path.dirname(ruta))
      File.write!(ruta, "esto no es json\n")
      on_exit(fn -> limpiar(%{personas: personas, mensajes: mensajes}) end)

      assert {:error, {:persistencia, {:linea_invalida, 1}}} =
               ServidorFamiliares.start_link(
                 name: :servidor_familiares_corrupto,
                 entidad_personas: personas,
                 entidad_mensajes: mensajes
               )
    end

    test "no inicia si un registro de mensajes está incompleto" do
      Process.flag(:trap_exit, true)
      sufijo = System.unique_integer([:positive])
      personas = :"personas_vacia_#{sufijo}"
      mensajes = :"mensajes_incompleta_#{sufijo}"
      ruta = Persistencia.ruta_archivo(mensajes)
      File.mkdir_p!(Path.dirname(ruta))
      File.write!(ruta, ~s({"id": "ME001"}\n))
      on_exit(fn -> limpiar(%{personas: personas, mensajes: mensajes}) end)

      assert {:error, {:persistencia, :registro_invalido}} =
               ServidorFamiliares.start_link(
                 name: :servidor_familiares_incompleto,
                 entidad_personas: personas,
                 entidad_mensajes: mensajes
               )
    end

    test "si no se puede guardar, el estado no cambia", %{servidor: s, entidades: entidades} do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)

      # Un directorio en lugar del archivo impide el renombrado final.
      File.rm!(Persistencia.ruta_archivo(entidades.personas))
      File.mkdir_p!(Persistencia.ruta_archivo(entidades.personas))

      assert {:error, {:persistencia, _}} = ServidorFamiliares.registrar_persona(persona(), s)

      assert {:error, {:persistencia, _}} =
               ServidorFamiliares.cambiar_estado("PE001", :localizada, s)

      assert ids(ServidorFamiliares.consultar_personas([], s)) == ["PE001"]
      assert {:ok, %{estado: :reportada}} = ServidorFamiliares.obtener_persona("PE001", s)
    end
  end

  describe "concurrencia" do
    test "50 registros simultáneos sin identificador no repiten ninguno", %{servidor: s} do
      resultados = en_paralelo(50, fn _ -> ServidorFamiliares.registrar_persona(persona(), s) end)

      assert Enum.all?(resultados, &match?({:ok, _}, &1))

      identificadores = Enum.map(resultados, fn {:ok, p} -> p.id end)
      assert length(Enum.uniq(identificadores)) == 50
      assert {:ok, lista} = ServidorFamiliares.consultar_personas([], s)
      assert length(lista) == 50
    end

    test "20 registros simultáneos del mismo documento: solo uno se acepta", %{servidor: s} do
      resultados =
        en_paralelo(20, fn _ ->
          ServidorFamiliares.registrar_persona(persona(%{documento: "DOC99999"}), s)
        end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :documento_existente})) == 19
      assert {:ok, [_]} = ServidorFamiliares.consultar_personas([documento: "DOC99999"], s)
    end

    test "20 cierres simultáneos del caso de una persona: solo uno se acepta", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.registrar_persona(persona(), s)
      {:ok, _} = ServidorFamiliares.cambiar_estado("PE001", :localizada, s)

      resultados =
        en_paralelo(20, fn _ -> ServidorFamiliares.cambiar_estado("PE001", :reunificada, s) end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :persona_reunificada})) == 19

      assert {:ok, persona} = ServidorFamiliares.obtener_persona("PE001", s)
      assert Enum.count(persona.historial, &(&1.estado == :reunificada)) == 1
    end

    test "50 mensajes simultáneos sin identificador no repiten ninguno", %{servidor: s} do
      resultados = en_paralelo(50, fn _ -> ServidorFamiliares.enviar_mensaje(mensaje(), s) end)

      assert Enum.all?(resultados, &match?({:ok, _}, &1))

      identificadores = Enum.map(resultados, fn {:ok, m} -> m.id end)
      assert length(Enum.uniq(identificadores)) == 50
    end

    test "20 entregas simultáneas del mismo mensaje: solo una se acepta", %{servidor: s} do
      {:ok, _} = ServidorFamiliares.enviar_mensaje(mensaje(), s)

      resultados = en_paralelo(20, fn _ -> ServidorFamiliares.marcar_entregado("ME001", s) end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :mensaje_entregado})) == 19
    end

    test "entregas simultáneas de pendientes: cada mensaje se entrega una sola vez", %{
      servidor: s
    } do
      for _ <- 1..30, do: {:ok, _} = ServidorFamiliares.enviar_mensaje(mensaje(), s)

      resultados = en_paralelo(10, fn _ -> ServidorFamiliares.entregar_pendientes("ana", s) end)

      entregados =
        Enum.flat_map(resultados, fn {:ok, lista} -> Enum.map(lista, & &1.id) end)

      assert length(entregados) == 30
      assert length(Enum.uniq(entregados)) == 30
      assert {:ok, []} = ServidorFamiliares.consultar_mensajes([estado: "pendiente"], s)
    end
  end
end
