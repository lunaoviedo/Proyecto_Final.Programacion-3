defmodule Emergencias.Comunidad.ComandosComunidad do
  @moduledoc """
  Interpreta los comandos de texto de la parte comunitaria: mascotas perdidas y
  encontradas, personas afectadas y mensajes entre familiares.

  Cada comando verifica primero los permisos de la sesión con
  `Emergencias.Usuarios.ServidorSesiones.autorizar/2`, valida sus argumentos y
  delega en los servidores de cada entidad. Si el comando no pertenece a este
  módulo, `ejecutar/3` retorna `:no_aplica` para que `Emergencias.Comandos` lo
  ofrezca a los demás módulos.

  ## Comandos de mascotas

      report_pet tipo especie color tamano zona contacto [nombre|-] [rasgos|-]
      list_pets [especie=..] [zona=..] [estado=..] [tipo=..]
      match_pets
      link_pets id_a id_b
      confirm_match id_a id_b
      discard_match id

  El nombre y los rasgos son opcionales; `-` indica que se omite el nombre. Los
  rasgos se separan con comas (`"collar rojo,cojea"`). La zona debe existir.

  ## Comandos de familiares

      report_person nombre documento edad zona [estado]
      find_person [nombre=..] [documento=..] [zona=..] [estado=..]
      update_person id estado
      person_history id
      send_family_message destinatario contenido
      list_family_messages

  El remitente de un mensaje es siempre el usuario de la sesión, y el destinatario
  debe ser un usuario registrado. Al listar sus mensajes, el usuario recibe los
  pendientes, que quedan entregados.

  ## Permisos

  Se emplean las acciones definidas en `Emergencias.Usuarios.Cuentas`:
  `:reportar_mascota` (`report_pet`, `list_pets`), `:cotejar_mascotas`
  (`match_pets`, `link_pets`, `confirm_match`, `discard_match`), `:reportar_persona`
  (`report_person`, `update_person`), `:buscar_persona` (`find_person`,
  `person_history`), `:enviar_mensaje_familiar` y `:listar_mensajes_familiares`.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  alias Emergencias.Familiares.{Mensajes, ServidorFamiliares}
  alias Emergencias.Mascotas.{Coincidencias, ServidorMascotas}
  alias Emergencias.Usuarios.ServidorSesiones
  alias Emergencias.Zonas.ServidorZonas

  @usos %{
    "report_pet" => "report_pet tipo especie color tamano zona contacto [nombre|-] [rasgos|-]",
    "match_pets" => "match_pets",
    "link_pets" => "link_pets id_a id_b",
    "confirm_match" => "confirm_match id_a id_b",
    "discard_match" => "discard_match id",
    "report_person" => "report_person nombre documento edad zona [estado]",
    "update_person" => "update_person id estado",
    "person_history" => "person_history id",
    "send_family_message" => "send_family_message destinatario contenido",
    "list_family_messages" => "list_family_messages"
  }

  @claves_mascotas %{
    "especie" => :especie,
    "zona" => :zona,
    "estado" => :estado,
    "tipo" => :tipo
  }

  @claves_personas %{
    "nombre" => :nombre,
    "documento" => :documento,
    "zona" => :zona,
    "estado" => :estado
  }

  @typedoc "Resultado de un comando."
  @type resultado :: {:ok, String.t(), String.t()} | {:error, String.t()} | :no_aplica

  # -- Mascotas ----------------------------------------------------------------

  @doc """
  Ejecuta un comando de mascotas o de familiares.

  Recibe el nombre del usuario de la sesión (o `nil`), el comando y sus argumentos
  ya separados. Retorna `{:ok, mensaje, sesion}`, `{:error, mensaje}` o `:no_aplica`
  si el comando no pertenece a este módulo.
  """
  @spec ejecutar(String.t() | nil, String.t(), [String.t()]) :: resultado()
  def ejecutar(sesion, "report_pet", [tipo, especie, color, tamano, zona, contacto | opcionales])
      when length(opcionales) <= 2 do
    con_permiso(sesion, :reportar_mascota, fn ->
      atributos =
        Map.merge(
          %{
            tipo: tipo,
            especie: especie,
            color: color,
            tamano: tamano,
            zona: zona,
            contacto: contacto
          },
          opciones_mascota(opcionales)
        )

      with :ok <- verificar_zona(zona),
           {:ok, mascota} <- ServidorMascotas.registrar(atributos) do
        {:ok,
         "Reporte #{mascota.id} registrado (#{mascota.tipo}, #{mascota.especie} #{mascota.color}).",
         sesion}
      else
        {:error, motivo} -> {:error, mensaje(motivo)}
      end
    end)
  end

  def ejecutar(_sesion, "report_pet", _args), do: uso("report_pet")

  def ejecutar(sesion, "list_pets", args) do
    con_permiso(sesion, :reportar_mascota, fn ->
      with {:ok, filtros} <- interpretar_filtros(args, @claves_mascotas, []),
           {:ok, mascotas} <- ServidorMascotas.consultar(filtros) do
        {:ok, listado(mascotas, "No hay reportes que mostrar.", &formatear_mascota/1), sesion}
      else
        {:error, motivo} -> {:error, mensaje(motivo)}
      end
    end)
  end

  def ejecutar(sesion, "match_pets", []) do
    con_permiso(sesion, :cotejar_mascotas, fn ->
      {:ok, formatear_coincidencias(ServidorMascotas.buscar_coincidencias()), sesion}
    end)
  end

  def ejecutar(_sesion, "match_pets", _args), do: uso("match_pets")

  def ejecutar(sesion, "link_pets", [id_a, id_b]) do
    con_permiso(sesion, :cotejar_mascotas, fn ->
      case ServidorMascotas.asociar(id_a, id_b) do
        {:ok, {a, b}} ->
          {:ok, "Reportes #{a.id} y #{b.id} marcados como posible coincidencia.", sesion}

        {:error, motivo} ->
          {:error, mensaje(motivo)}
      end
    end)
  end

  def ejecutar(_sesion, "link_pets", _args), do: uso("link_pets")

  def ejecutar(sesion, "confirm_match", [id_a, id_b]) do
    con_permiso(sesion, :cotejar_mascotas, fn ->
      case ServidorMascotas.confirmar(id_a, id_b) do
        {:ok, {a, b}} ->
          {:ok, "Coincidencia confirmada: #{a.id} y #{b.id} quedaron resueltos.", sesion}

        {:error, motivo} ->
          {:error, mensaje(motivo)}
      end
    end)
  end

  def ejecutar(_sesion, "confirm_match", _args), do: uso("confirm_match")

  def ejecutar(sesion, "discard_match", [id]) do
    con_permiso(sesion, :cotejar_mascotas, fn ->
      case ServidorMascotas.descartar(id) do
        {:ok, {a, b}} ->
          {:ok, "Coincidencia descartada: #{a.id} y #{b.id} volvieron a estar activos.", sesion}

        {:error, motivo} ->
          {:error, mensaje(motivo)}
      end
    end)
  end

  def ejecutar(_sesion, "discard_match", _args), do: uso("discard_match")

  # -- Personas ----------------------------------------------------------------

  def ejecutar(sesion, "report_person", [nombre, documento, edad, zona | opcionales])
      when length(opcionales) <= 1 do
    con_permiso(sesion, :reportar_persona, fn ->
      atributos =
        con_estado(%{nombre: nombre, documento: documento, edad: edad, zona: zona}, opcionales)

      with :ok <- verificar_zona(zona),
           {:ok, persona} <- ServidorFamiliares.registrar_persona(atributos) do
        {:ok,
         "Persona #{persona.nombre} registrada con el identificador #{persona.id} (#{persona.estado}).",
         sesion}
      else
        {:error, motivo} -> {:error, mensaje(motivo)}
      end
    end)
  end

  def ejecutar(_sesion, "report_person", _args), do: uso("report_person")

  def ejecutar(sesion, "find_person", args) do
    con_permiso(sesion, :buscar_persona, fn ->
      with {:ok, filtros} <- interpretar_filtros(args, @claves_personas, []),
           {:ok, personas} <- ServidorFamiliares.consultar_personas(filtros) do
        {:ok, listado(personas, "No se encontraron personas.", &formatear_persona/1), sesion}
      else
        {:error, motivo} -> {:error, mensaje(motivo)}
      end
    end)
  end

  def ejecutar(sesion, "update_person", [id, estado]) do
    con_permiso(sesion, :reportar_persona, fn ->
      case ServidorFamiliares.cambiar_estado(id, estado) do
        {:ok, persona} ->
          {:ok, "Persona #{persona.id}: nuevo estado #{persona.estado}.", sesion}

        {:error, motivo} ->
          {:error, mensaje(motivo)}
      end
    end)
  end

  def ejecutar(_sesion, "update_person", _args), do: uso("update_person")

  def ejecutar(sesion, "person_history", [id]) do
    con_permiso(sesion, :buscar_persona, fn ->
      case ServidorFamiliares.obtener_persona(id) do
        {:ok, persona} -> {:ok, formatear_historial(persona), sesion}
        {:error, motivo} -> {:error, mensaje(motivo)}
      end
    end)
  end

  def ejecutar(_sesion, "person_history", _args), do: uso("person_history")

  # -- Mensajes ----------------------------------------------------------------

  def ejecutar(sesion, "send_family_message", [destinatario | palabras]) when palabras != [] do
    con_permiso(sesion, :enviar_mensaje_familiar, fn ->
      atributos = %{
        remitente: sesion,
        destinatario: destinatario,
        contenido: Enum.join(palabras, " ")
      }

      with :ok <- verificar_usuario(destinatario),
           {:ok, enviado} <- ServidorFamiliares.enviar_mensaje(atributos) do
        {:ok, "Mensaje #{enviado.id} enviado a #{enviado.destinatario}.", sesion}
      else
        {:error, motivo} -> {:error, mensaje(motivo)}
      end
    end)
  end

  def ejecutar(_sesion, "send_family_message", _args), do: uso("send_family_message")

  def ejecutar(sesion, "list_family_messages", []) do
    con_permiso(sesion, :listar_mensajes_familiares, fn ->
      with {:ok, nuevos} <- ServidorFamiliares.entregar_pendientes(sesion),
           {:ok, mensajes} <- ServidorFamiliares.consultar_mensajes(usuario: sesion) do
        ids_nuevos = MapSet.new(nuevos, & &1.id)

        {:ok, listado(mensajes, "No tienes mensajes.", &formatear_mensaje(&1, ids_nuevos)),
         sesion}
      else
        {:error, motivo} -> {:error, mensaje(motivo)}
      end
    end)
  end

  def ejecutar(_sesion, "list_family_messages", _args), do: uso("list_family_messages")

  # Si no es ninguno de los anteriores, no aplica a este módulo.
  def ejecutar(_sesion, _comando, _args), do: :no_aplica

  # -- Permisos y validaciones -------------------------------------------------

  defp con_permiso(sesion, accion, funcion) do
    case ServidorSesiones.autorizar(sesion, accion) do
      {:ok, _usuario} ->
        case funcion.() do
          {:ok, _mensaje, _sesion} = resultado ->
            ServidorSesiones.registrar_actividad(sesion, Atom.to_string(accion))
            resultado

          error ->
            error
        end

      {:error, motivo} ->
        {:error, mensaje(motivo)}
    end
  end

  defp uso(comando), do: {:error, "Uso: " <> Map.fetch!(@usos, comando)}

  defp verificar_zona(codigo) do
    case ServidorZonas.obtener_zona(codigo) do
      {:ok, _zona} -> :ok
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp verificar_usuario(nombre) do
    case ServidorSesiones.obtener_usuario(nombre) do
      {:ok, _usuario} -> :ok
      :error -> {:error, :destinatario_no_encontrado}
    end
  end

  # -- Interpretación de argumentos --------------------------------------------

  defp opciones_mascota([]), do: %{}
  defp opciones_mascota([nombre]), do: %{nombre: nombre_o_nulo(nombre)}

  defp opciones_mascota([nombre, rasgos]),
    do: %{nombre: nombre_o_nulo(nombre), caracteristicas: separar_rasgos(rasgos)}

  defp nombre_o_nulo("-"), do: nil
  defp nombre_o_nulo(nombre), do: nombre

  defp separar_rasgos("-"), do: []
  defp separar_rasgos(rasgos), do: String.split(rasgos, ",")

  defp con_estado(atributos, []), do: atributos
  defp con_estado(atributos, [estado]), do: Map.put(atributos, :estado, estado)

  # Convierte recursivamente los argumentos `clave=valor` en una lista de filtros.
  # Las claves se traducen con una tabla explícita, sin crear átomos nuevos.
  defp interpretar_filtros([], _claves, acumulados), do: {:ok, Enum.reverse(acumulados)}

  defp interpretar_filtros([argumento | resto], claves, acumulados) do
    with [clave, valor] <- String.split(argumento, "=", parts: 2),
         {:ok, atomo} <- Map.fetch(claves, clave) do
      interpretar_filtros(resto, claves, [{atomo, valor} | acumulados])
    else
      _ -> {:error, {:filtro_invalido, argumento}}
    end
  end

  # -- Presentación ------------------------------------------------------------

  defp listado([], vacio, _formato), do: vacio

  defp listado(elementos, _vacio, formato) do
    elementos
    |> Util2.convertir_coleccion_mensaje(&(formato.(&1) <> "\n"))
    |> Enum.join()
    |> String.trim_trailing()
  end

  defp formatear_mascota(m) do
    nombre = m.nombre || "sin nombre"

    rasgos =
      case m.caracteristicas do
        [] -> "sin rasgos"
        lista -> Enum.join(lista, ", ")
      end

    pareja = if m.coincidencia_con, do: ", pareja: #{m.coincidencia_con}", else: ""

    " - #{m.id} [#{m.tipo}, #{m.estado}] #{m.especie} #{m.color} #{m.tamano}, " <>
      "zona #{m.zona}, nombre: #{nombre}, rasgos: #{rasgos}, contacto: #{m.contacto}#{pareja}"
  end

  defp formatear_coincidencias([]) do
    "No hay posibles coincidencias (mínimo #{Coincidencias.umbral()} de " <>
      "#{Coincidencias.puntaje_maximo()} puntos)."
  end

  defp formatear_coincidencias(coincidencias) do
    encabezado =
      "Posibles coincidencias (mínimo #{Coincidencias.umbral()} de " <>
        "#{Coincidencias.puntaje_maximo()} puntos):\n"

    encabezado <> listado(coincidencias, "", &formatear_coincidencia/1)
  end

  defp formatear_coincidencia(c) do
    d = c.desglose

    " - #{c.perdida} (perdida) ~ #{c.encontrada} (encontrada): #{c.puntaje} puntos " <>
      "[color #{d.color}, tamaño #{d.tamano}, zona #{d.zona}, " <>
      "nombre #{d.nombre}, rasgos #{d.caracteristicas}]"
  end

  defp formatear_persona(p),
    do: " - #{p.id} #{p.nombre} (doc. #{p.documento}, #{p.edad} años) zona #{p.zona}: #{p.estado}"

  defp formatear_historial(persona) do
    cambios =
      Enum.map(persona.historial, fn cambio ->
        "  - #{cambio.estado} (#{formatear_fecha(cambio.fecha)})"
      end)

    Enum.join(["Historial de #{persona.nombre} (#{persona.id}):" | cambios], "\n")
  end

  defp formatear_mensaje(m, ids_nuevos) do
    etiqueta = if MapSet.member?(ids_nuevos, m.id), do: "nuevo", else: m.estado

    " - #{m.id} [#{formatear_fecha(m.fecha)}] #{m.remitente} -> #{m.destinatario} " <>
      "(#{etiqueta}): #{m.contenido}"
  end

  defp formatear_fecha(fecha), do: Calendar.strftime(fecha, "%Y-%m-%d %H:%M")

  # -- Mensajes de error -------------------------------------------------------

  defp mensaje(:no_autorizado), do: "No tienes permiso para ejecutar este comando."
  defp mensaje(:no_conectado), do: "Debes conectarte primero: connect usuario clave tipo zona"
  defp mensaje(:zona_no_encontrada), do: "La zona no existe."
  defp mensaje(:destinatario_no_encontrado), do: "El destinatario no es un usuario registrado."
  defp mensaje(:atributos_invalidos), do: "Los datos del comando no son válidos."
  defp mensaje(:filtros_invalidos), do: "Los filtros no son válidos."
  defp mensaje({:filtro_invalido, filtro}), do: "Filtro inválido: #{filtro}"
  defp mensaje({:persistencia, motivo}), do: "No se pudo guardar: #{inspect(motivo)}"

  # Mascotas
  defp mensaje(:id_invalido), do: "Identificador inválido."
  defp mensaje(:id_existente), do: "El identificador ya está en uso."
  defp mensaje(:tipo_invalido), do: "Tipo inválido (perdida o encontrada)."
  defp mensaje(:especie_invalida), do: "Especie inválida."
  defp mensaje(:color_invalido), do: "Color inválido."
  defp mensaje(:tamano_invalido), do: "Tamaño inválido (pequeno, mediano o grande)."
  defp mensaje(:zona_invalida), do: "Zona inválida."
  defp mensaje(:contacto_invalido), do: "Contacto inválido."
  defp mensaje(:caracteristicas_invalidas), do: "Rasgos inválidos."
  defp mensaje(:reporte_no_encontrado), do: "El reporte no existe."
  defp mensaje(:reporte_resuelto), do: "El reporte ya está resuelto."
  defp mensaje(:mismo_reporte), do: "Debes indicar dos reportes distintos."
  defp mensaje(:tipos_iguales), do: "Los reportes deben ser de tipo contrario."
  defp mensaje(:ya_asociado_a_otro), do: "Uno de los reportes ya está asociado a otro."

  defp mensaje(:sin_coincidencia_pendiente),
    do: "El reporte no tiene una posible coincidencia pendiente."

  # Personas
  defp mensaje(:nombre_invalido), do: "Nombre inválido."
  defp mensaje(:documento_invalido), do: "Documento inválido (5 a 15 letras o dígitos)."
  defp mensaje(:documento_existente), do: "Ya hay una persona registrada con ese documento."
  defp mensaje(:edad_invalida), do: "Edad inválida (entero entre 0 y 120)."

  defp mensaje(:estado_invalido), do: "Estado inválido."

  defp mensaje(:estado_inicial_invalido),
    do: "El estado inicial debe ser reportada o sin_informacion."

  defp mensaje(:persona_no_encontrada), do: "La persona no existe."
  defp mensaje(:persona_reunificada), do: "El caso de la persona ya está cerrado (reunificada)."

  defp mensaje({:transicion_invalida, actual, destino}),
    do: "Cambio de estado no permitido: #{actual} -> #{destino}."

  # Mensajes entre familiares
  defp mensaje(:remitente_invalido), do: "Remitente inválido."
  defp mensaje(:destinatario_invalido), do: "Destinatario inválido."
  defp mensaje(:destinatario_es_remitente), do: "No puedes enviarte un mensaje a ti mismo."
  defp mensaje(:contenido_invalido), do: "El contenido del mensaje no puede estar vacío."

  defp mensaje(:contenido_demasiado_largo),
    do: "El mensaje supera los #{Mensajes.largo_maximo()} caracteres."

  defp mensaje(:mensaje_no_encontrado), do: "El mensaje no existe."
  defp mensaje(:mensaje_entregado), do: "El mensaje ya fue entregado."

  defp mensaje(otro), do: "Error: #{inspect(otro)}"
end
