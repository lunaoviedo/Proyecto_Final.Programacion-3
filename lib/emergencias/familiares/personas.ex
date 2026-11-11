defmodule Emergencias.Familiares.Personas do
  @moduledoc """
  Lógica de dominio de las personas afectadas por la emergencia.

  Las funciones son puras: reciben el mapa de personas (identificador => persona)
  y retornan `{:ok, nuevas_personas, valor}` o `{:error, motivo}`, sin lanzar
  excepciones ante situaciones esperadas. La persistencia y la concurrencia
  corresponden al servidor de familiares.

  Las funciones que registran un cambio reciben el instante en que ocurre; si se
  omite, se usa la hora actual UTC con precisión de segundos.

  ## Estados y transiciones

  Una persona se registra como `:reportada` o, si solo se sabe que se la busca,
  como `:sin_informacion`. Los cambios permitidos son:

      sin_informacion -> reportada | localizada
      reportada       -> localizada
      localizada      -> trasladada | en_albergue | reunificada
      trasladada      -> en_albergue | reunificada
      en_albergue     -> trasladada | reunificada
      reunificada     -> (estado final)

  El estado `:reunificada` es final: el caso no puede cerrarse dos veces ni
  reabrirse. Cada cambio queda anotado en el historial de la persona.

  ## Identidad

  El identificador y el documento no pueden repetirse, de modo que una misma persona
  no tenga dos registros.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  alias Emergencias.Familiares.Persona

  @typedoc "Colección de personas indexada por identificador."
  @type personas :: %{optional(String.t()) => Persona.t()}

  @typedoc "Motivo de un error de dominio."
  @type motivo :: atom() | tuple()

  @transiciones %{
    sin_informacion: [:reportada, :localizada],
    reportada: [:localizada],
    localizada: [:trasladada, :en_albergue, :reunificada],
    trasladada: [:en_albergue, :reunificada],
    en_albergue: [:trasladada, :reunificada],
    reunificada: []
  }

  @estados_iniciales [:sin_informacion, :reportada]
  @edad_maxima 120

  # -- Registro ----------------------------------------------------------------

  @doc """
  Registra una persona nueva y anota su estado inicial en el historial.

  `atributos` es un mapa con las claves `:id`, `:nombre`, `:documento`, `:edad`,
  `:zona` y, opcionalmente, `:estado` (`:reportada` por defecto, o
  `:sin_informacion`). El documento admite de 5 a 15 letras o dígitos y se guarda en
  mayúsculas. La edad admite un entero entre 0 y 120 o su texto equivalente.
  """
  @spec registrar(personas(), map(), DateTime.t()) ::
          {:ok, personas(), Persona.t()} | {:error, motivo()}
  def registrar(personas, atributos, ahora \\ DateTime.utc_now(:second))
      when is_map(personas) and is_map(atributos) and is_struct(ahora, DateTime) do
    with {:ok, id} <- texto(atributos[:id], :id_invalido),
         :ok <- verificar_id_libre(personas, id),
         {:ok, nombre} <- texto(atributos[:nombre], :nombre_invalido),
         {:ok, documento} <- interpretar_documento(atributos[:documento]),
         :ok <- verificar_documento_libre(personas, documento),
         {:ok, edad} <- interpretar_edad(atributos[:edad]),
         {:ok, zona} <- texto(atributos[:zona], :zona_invalida),
         {:ok, estado} <- interpretar_estado_inicial(Map.get(atributos, :estado, :reportada)) do
      persona = %Persona{
        id: id,
        nombre: nombre,
        documento: documento,
        edad: edad,
        zona: zona,
        estado: estado,
        historial: [%{estado: estado, fecha: ahora}]
      }

      {:ok, Map.put(personas, id, persona), persona}
    end
  end

  @doc """
  Genera el siguiente identificador libre, con el formato `PE001`, `PE002`, etc.

  ## Ejemplos

      iex> Emergencias.Familiares.Personas.siguiente_id(%{})
      "PE001"

  """
  @spec siguiente_id(personas()) :: String.t()
  def siguiente_id(personas), do: generar_id(personas, map_size(personas) + 1)

  defp generar_id(personas, numero) do
    id = "PE" <> String.pad_leading(Integer.to_string(numero), 3, "0")

    if Map.has_key?(personas, id), do: generar_id(personas, numero + 1), else: id
  end

  # -- Consultas ---------------------------------------------------------------

  @doc """
  Retorna la persona con el identificador dado.
  """
  @spec obtener(personas(), String.t()) :: {:ok, Persona.t()} | {:error, :persona_no_encontrada}
  def obtener(personas, id) do
    case Map.fetch(personas, id) do
      {:ok, persona} -> {:ok, persona}
      :error -> {:error, :persona_no_encontrada}
    end
  end

  @doc """
  Consulta las personas que cumplen todos los filtros, ordenadas por identificador.

  Los filtros son una lista de pares con las claves `:nombre`, `:documento`, `:zona`
  y `:estado`. El nombre se busca como fragmento, sin distinguir mayúsculas ni tildes;
  el resto de claves exige coincidencia exacta. Sin filtros retorna todas las personas.
  """
  @spec consultar(personas(), keyword()) :: {:ok, [Persona.t()]} | {:error, motivo()}
  def consultar(personas, filtros \\ []) when is_map(personas) and is_list(filtros) do
    with {:ok, filtros} <- normalizar_filtros(filtros) do
      lista = personas |> Map.values() |> Enum.sort_by(& &1.id)
      {:ok, Enum.filter(lista, &cumple?(&1, filtros))}
    end
  end

  defp normalizar_filtros([]), do: {:ok, []}

  defp normalizar_filtros([{clave, valor} | resto])
       when clave in [:nombre, :documento, :zona, :estado] do
    with {:ok, normalizado} <- normalizar_filtro(clave, valor),
         {:ok, otros} <- normalizar_filtros(resto) do
      {:ok, [{clave, normalizado} | otros]}
    end
  end

  defp normalizar_filtros([{clave, _valor} | _resto]), do: {:error, {:filtro_invalido, clave}}
  defp normalizar_filtros([otro | _resto]), do: {:error, {:filtro_invalido, otro}}

  defp normalizar_filtro(:nombre, valor) when is_binary(valor) do
    case normalizar_nombre(valor) do
      "" -> {:error, {:filtro_invalido, :nombre}}
      fragmento -> {:ok, fragmento}
    end
  end

  defp normalizar_filtro(:documento, valor) when is_binary(valor),
    do: {:ok, valor |> String.trim() |> String.upcase()}

  defp normalizar_filtro(:zona, valor) when is_binary(valor), do: {:ok, String.trim(valor)}
  defp normalizar_filtro(:estado, valor), do: interpretar_estado(valor)
  defp normalizar_filtro(clave, _valor), do: {:error, {:filtro_invalido, clave}}

  defp cumple?(_persona, []), do: true

  defp cumple?(persona, [{:nombre, fragmento} | resto]),
    do: String.contains?(normalizar_nombre(persona.nombre), fragmento) and cumple?(persona, resto)

  defp cumple?(persona, [{:documento, valor} | resto]),
    do: persona.documento == valor and cumple?(persona, resto)

  defp cumple?(persona, [{:zona, valor} | resto]),
    do: persona.zona == valor and cumple?(persona, resto)

  defp cumple?(persona, [{:estado, valor} | resto]),
    do: persona.estado == valor and cumple?(persona, resto)

  # -- Cambios de estado -------------------------------------------------------

  @doc """
  Indica si una persona puede pasar del estado `desde` al estado `hacia`.

  ## Ejemplos

      iex> Emergencias.Familiares.Personas.transicion_valida?(:localizada, :en_albergue)
      true

      iex> Emergencias.Familiares.Personas.transicion_valida?(:reunificada, :localizada)
      false

  """
  @spec transicion_valida?(Persona.estado(), Persona.estado()) :: boolean()
  def transicion_valida?(desde, hacia), do: hacia in Map.get(@transiciones, desde, [])

  @doc """
  Cambia el estado de una persona y lo anota en su historial.

  El nuevo estado admite un átomo o su texto. Retorna `{:error, :persona_reunificada}`
  si el caso ya estaba cerrado y `{:error, {:transicion_invalida, actual, destino}}`
  si el cambio no está permitido.
  """
  @spec cambiar_estado(personas(), String.t(), Persona.estado() | String.t(), DateTime.t()) ::
          {:ok, personas(), Persona.t()} | {:error, motivo()}
  def cambiar_estado(personas, id, nuevo_estado, ahora \\ DateTime.utc_now(:second))
      when is_map(personas) and is_struct(ahora, DateTime) do
    with {:ok, persona} <- obtener(personas, id),
         {:ok, destino} <- interpretar_estado(nuevo_estado),
         :ok <- verificar_abierta(persona),
         :ok <- verificar_transicion(persona, destino) do
      actualizada = %{
        persona
        | estado: destino,
          historial: persona.historial ++ [%{estado: destino, fecha: ahora}]
      }

      {:ok, Map.put(personas, id, actualizada), actualizada}
    end
  end

  defp verificar_abierta(%Persona{estado: :reunificada}), do: {:error, :persona_reunificada}
  defp verificar_abierta(_persona), do: :ok

  defp verificar_transicion(%Persona{estado: actual}, destino) do
    if transicion_valida?(actual, destino),
      do: :ok,
      else: {:error, {:transicion_invalida, actual, destino}}
  end

  # -- Persistencia ------------------------------------------------------------

  @doc """
  Convierte una persona en un mapa plano apto para persistencia.
  """
  @spec a_registro(Persona.t()) :: map()
  def a_registro(%Persona{} = p) do
    %{
      "id" => p.id,
      "nombre" => p.nombre,
      "documento" => p.documento,
      "edad" => p.edad,
      "zona" => p.zona,
      "estado" => Atom.to_string(p.estado),
      "historial" =>
        Enum.map(p.historial, fn cambio ->
          %{
            "estado" => Atom.to_string(cambio.estado),
            "fecha" => DateTime.to_iso8601(cambio.fecha)
          }
        end)
    }
  end

  @doc """
  Reconstruye una persona a partir de un registro persistido.
  """
  @spec de_registro(map()) :: {:ok, Persona.t()} | {:error, motivo()}
  def de_registro(
        %{
          "id" => id,
          "nombre" => nombre,
          "documento" => documento,
          "edad" => edad,
          "zona" => zona
        } = registro
      )
      when is_binary(id) and is_binary(nombre) and is_binary(documento) and is_binary(zona) do
    with {:ok, edad} <- interpretar_edad(edad),
         {:ok, estado} <- interpretar_estado(Map.get(registro, "estado", "reportada")),
         {:ok, historial} <- interpretar_historial(Map.get(registro, "historial", []), []) do
      {:ok,
       %Persona{
         id: id,
         nombre: nombre,
         documento: documento,
         edad: edad,
         zona: zona,
         estado: estado,
         historial: historial
       }}
    end
  end

  def de_registro(_registro), do: {:error, :registro_invalido}

  defp interpretar_historial([], acumulados), do: {:ok, Enum.reverse(acumulados)}

  defp interpretar_historial([%{"estado" => estado, "fecha" => fecha} | resto], acumulados)
       when is_binary(fecha) do
    with {:ok, estado} <- interpretar_estado(estado),
         {:ok, fecha, _desfase} <- leer_fecha(fecha) do
      interpretar_historial(resto, [%{estado: estado, fecha: fecha} | acumulados])
    end
  end

  defp interpretar_historial(lista, _acumulados) when is_list(lista),
    do: {:error, :historial_invalido}

  defp interpretar_historial(_otro, _acumulados), do: {:error, :historial_invalido}

  defp leer_fecha(texto) do
    case DateTime.from_iso8601(texto) do
      {:ok, _fecha, _desfase} = ok -> ok
      {:error, _motivo} -> {:error, :fecha_invalida}
    end
  end

  # -- Validación y conversión -------------------------------------------------

  defp verificar_id_libre(personas, id) do
    if Map.has_key?(personas, id), do: {:error, :id_existente}, else: :ok
  end

  defp verificar_documento_libre(personas, documento) do
    if Enum.any?(personas, fn {_id, persona} -> persona.documento == documento end),
      do: {:error, :documento_existente},
      else: :ok
  end

  defp texto(valor, error) when is_binary(valor) do
    case String.trim(valor) do
      "" -> {:error, error}
      limpio -> {:ok, limpio}
    end
  end

  defp texto(_valor, error), do: {:error, error}

  defp interpretar_documento(documento) when is_integer(documento) and documento > 0,
    do: interpretar_documento(Integer.to_string(documento))

  defp interpretar_documento(documento) when is_binary(documento) do
    limpio = documento |> String.trim() |> String.upcase()

    if Regex.match?(~r/\A[0-9A-Z]{5,15}\z/, limpio),
      do: {:ok, limpio},
      else: {:error, :documento_invalido}
  end

  defp interpretar_documento(_documento), do: {:error, :documento_invalido}

  defp interpretar_edad(edad) when is_integer(edad) and edad >= 0 and edad <= @edad_maxima,
    do: {:ok, edad}

  defp interpretar_edad(edad) when is_binary(edad) do
    case Integer.parse(String.trim(edad)) do
      {numero, ""} -> interpretar_edad(numero)
      _ -> {:error, :edad_invalida}
    end
  end

  defp interpretar_edad(_edad), do: {:error, :edad_invalida}

  defp interpretar_estado(estado) when is_atom(estado) and not is_nil(estado) do
    if estado in Persona.estados(), do: {:ok, estado}, else: {:error, :estado_invalido}
  end

  defp interpretar_estado(estado) when is_binary(estado) do
    case estado |> String.trim() |> String.downcase() do
      "sin_informacion" -> {:ok, :sin_informacion}
      "reportada" -> {:ok, :reportada}
      "localizada" -> {:ok, :localizada}
      "trasladada" -> {:ok, :trasladada}
      "en_albergue" -> {:ok, :en_albergue}
      "reunificada" -> {:ok, :reunificada}
      _ -> {:error, :estado_invalido}
    end
  end

  defp interpretar_estado(_estado), do: {:error, :estado_invalido}

  defp interpretar_estado_inicial(estado) do
    with {:ok, estado} <- interpretar_estado(estado) do
      if estado in @estados_iniciales, do: {:ok, estado}, else: {:error, :estado_inicial_invalido}
    end
  end

  # Quita tildes y mayúsculas para comparar nombres.
  defp normalizar_nombre(texto) do
    texto
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.trim()
  end
end
