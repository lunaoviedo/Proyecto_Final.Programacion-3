defmodule Emergencias.Familiares.Mensajes do
  @moduledoc """
  Lógica de dominio de los mensajes entre familiares.

  Las funciones son puras: reciben el mapa de mensajes (identificador => mensaje)
  y retornan `{:ok, nuevos_mensajes, valor}` o `{:error, motivo}`, sin lanzar
  excepciones ante situaciones esperadas. La persistencia y la concurrencia
  corresponden al servidor de familiares.

  Esta capa solo valida el formato del remitente y del destinatario; comprobar que
  el destinatario sea un usuario existente corresponde a quien invoca.

  ## Estados y transiciones

      pendiente -> entregado

  El estado `:entregado` es final: un mensaje no puede entregarse dos veces.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  alias Emergencias.Familiares.Mensaje

  @typedoc "Colección de mensajes indexada por identificador."
  @type mensajes :: %{optional(String.t()) => Mensaje.t()}

  @typedoc "Motivo de un error de dominio."
  @type motivo :: atom() | tuple()

  @largo_maximo 500

  # -- Envío -------------------------------------------------------------------

  @doc """
  Retorna el largo máximo permitido para el contenido de un mensaje.

  ## Ejemplos

      iex> Emergencias.Familiares.Mensajes.largo_maximo()
      500

  """
  @spec largo_maximo() :: pos_integer()
  def largo_maximo, do: @largo_maximo

  @doc """
  Registra un mensaje nuevo en estado `:pendiente`.

  `atributos` es un mapa con las claves `:id`, `:remitente`, `:destinatario` y
  `:contenido`. El contenido admite hasta 500 caracteres y el remitente debe ser
  distinto del destinatario. La fecha es el instante del envío.
  """
  @spec enviar(mensajes(), map(), DateTime.t()) ::
          {:ok, mensajes(), Mensaje.t()} | {:error, motivo()}
  def enviar(mensajes, atributos, ahora \\ DateTime.utc_now(:second))
      when is_map(mensajes) and is_map(atributos) and is_struct(ahora, DateTime) do
    with {:ok, id} <- texto(atributos[:id], :id_invalido),
         :ok <- verificar_id_libre(mensajes, id),
         {:ok, remitente} <- texto(atributos[:remitente], :remitente_invalido),
         {:ok, destinatario} <- texto(atributos[:destinatario], :destinatario_invalido),
         :ok <- verificar_distintos(remitente, destinatario),
         {:ok, contenido} <- interpretar_contenido(atributos[:contenido]) do
      mensaje = %Mensaje{
        id: id,
        fecha: ahora,
        remitente: remitente,
        destinatario: destinatario,
        contenido: contenido
      }

      {:ok, Map.put(mensajes, id, mensaje), mensaje}
    end
  end

  @doc """
  Genera el siguiente identificador libre, con el formato `ME001`, `ME002`, etc.

  ## Ejemplos

      iex> Emergencias.Familiares.Mensajes.siguiente_id(%{})
      "ME001"

  """
  @spec siguiente_id(mensajes()) :: String.t()
  def siguiente_id(mensajes), do: generar_id(mensajes, map_size(mensajes) + 1)

  defp generar_id(mensajes, numero) do
    id = "ME" <> String.pad_leading(Integer.to_string(numero), 3, "0")

    if Map.has_key?(mensajes, id), do: generar_id(mensajes, numero + 1), else: id
  end

  # -- Consultas ---------------------------------------------------------------

  @doc """
  Retorna el mensaje con el identificador dado.
  """
  @spec obtener(mensajes(), String.t()) :: {:ok, Mensaje.t()} | {:error, :mensaje_no_encontrado}
  def obtener(mensajes, id) do
    case Map.fetch(mensajes, id) do
      {:ok, mensaje} -> {:ok, mensaje}
      :error -> {:error, :mensaje_no_encontrado}
    end
  end

  @doc """
  Consulta los mensajes que cumplen todos los filtros, ordenados por identificador
  (que coincide con el orden de envío).

  Los filtros son una lista de pares con las claves `:remitente`, `:destinatario`,
  `:usuario` (mensajes enviados o recibidos por ese usuario) y `:estado`. Sin
  filtros retorna todos los mensajes.
  """
  @spec consultar(mensajes(), keyword()) :: {:ok, [Mensaje.t()]} | {:error, motivo()}
  def consultar(mensajes, filtros \\ []) when is_map(mensajes) and is_list(filtros) do
    with {:ok, filtros} <- normalizar_filtros(filtros) do
      lista = mensajes |> Map.values() |> Enum.sort_by(& &1.id)
      {:ok, Enum.filter(lista, &cumple?(&1, filtros))}
    end
  end

  defp normalizar_filtros([]), do: {:ok, []}

  defp normalizar_filtros([{clave, valor} | resto])
       when clave in [:remitente, :destinatario, :usuario, :estado] do
    with {:ok, normalizado} <- normalizar_filtro(clave, valor),
         {:ok, otros} <- normalizar_filtros(resto) do
      {:ok, [{clave, normalizado} | otros]}
    end
  end

  defp normalizar_filtros([{clave, _valor} | _resto]), do: {:error, {:filtro_invalido, clave}}
  defp normalizar_filtros([otro | _resto]), do: {:error, {:filtro_invalido, otro}}

  defp normalizar_filtro(:estado, valor), do: interpretar_estado(valor)

  defp normalizar_filtro(clave, valor) when is_binary(valor) do
    case String.trim(valor) do
      "" -> {:error, {:filtro_invalido, clave}}
      limpio -> {:ok, limpio}
    end
  end

  defp normalizar_filtro(clave, _valor), do: {:error, {:filtro_invalido, clave}}

  defp cumple?(_mensaje, []), do: true

  defp cumple?(mensaje, [{:remitente, valor} | resto]),
    do: mensaje.remitente == valor and cumple?(mensaje, resto)

  defp cumple?(mensaje, [{:destinatario, valor} | resto]),
    do: mensaje.destinatario == valor and cumple?(mensaje, resto)

  defp cumple?(mensaje, [{:usuario, valor} | resto]),
    do: valor in [mensaje.remitente, mensaje.destinatario] and cumple?(mensaje, resto)

  defp cumple?(mensaje, [{:estado, valor} | resto]),
    do: mensaje.estado == valor and cumple?(mensaje, resto)

  # -- Entrega -----------------------------------------------------------------

  @doc """
  Indica si un mensaje puede pasar del estado `desde` al estado `hacia`.

  ## Ejemplos

      iex> Emergencias.Familiares.Mensajes.transicion_valida?(:pendiente, :entregado)
      true

      iex> Emergencias.Familiares.Mensajes.transicion_valida?(:entregado, :pendiente)
      false

  """
  @spec transicion_valida?(Mensaje.estado(), Mensaje.estado()) :: boolean()
  def transicion_valida?(:pendiente, :entregado), do: true
  def transicion_valida?(_desde, _hacia), do: false

  @doc """
  Marca un mensaje como entregado.

  Retorna `{:error, :mensaje_entregado}` si ya había sido entregado.
  """
  @spec marcar_entregado(mensajes(), String.t()) ::
          {:ok, mensajes(), Mensaje.t()} | {:error, motivo()}
  def marcar_entregado(mensajes, id) when is_map(mensajes) do
    with {:ok, mensaje} <- obtener(mensajes, id),
         :ok <- verificar_pendiente(mensaje) do
      entregado = %{mensaje | estado: :entregado}
      {:ok, Map.put(mensajes, id, entregado), entregado}
    end
  end

  @doc """
  Marca como entregados todos los mensajes pendientes dirigidos a un destinatario.

  Retorna los mensajes entregados, ordenados por identificador; la lista es vacía si
  no había ninguno pendiente.
  """
  @spec entregar_pendientes(mensajes(), String.t()) ::
          {:ok, mensajes(), [Mensaje.t()]} | {:error, motivo()}
  def entregar_pendientes(mensajes, destinatario) when is_map(mensajes) do
    with {:ok, destinatario} <- texto(destinatario, :destinatario_invalido) do
      pendientes =
        mensajes
        |> Map.values()
        |> Enum.filter(&(&1.destinatario == destinatario and &1.estado == :pendiente))
        |> Enum.sort_by(& &1.id)

      {nuevos, entregados} = entregar_todos(pendientes, mensajes, [])
      {:ok, nuevos, entregados}
    end
  end

  # Recorre recursivamente la lista de pendientes marcando cada mensaje.
  defp entregar_todos([], mensajes, entregados), do: {mensajes, Enum.reverse(entregados)}

  defp entregar_todos([mensaje | resto], mensajes, entregados) do
    entregado = %{mensaje | estado: :entregado}
    entregar_todos(resto, Map.put(mensajes, mensaje.id, entregado), [entregado | entregados])
  end

  defp verificar_pendiente(%Mensaje{estado: :pendiente}), do: :ok
  defp verificar_pendiente(%Mensaje{estado: :entregado}), do: {:error, :mensaje_entregado}

  # -- Persistencia ------------------------------------------------------------

  @doc """
  Convierte un mensaje en un mapa plano apto para persistencia.
  """
  @spec a_registro(Mensaje.t()) :: map()
  def a_registro(%Mensaje{} = m) do
    %{
      "id" => m.id,
      "fecha" => DateTime.to_iso8601(m.fecha),
      "remitente" => m.remitente,
      "destinatario" => m.destinatario,
      "contenido" => m.contenido,
      "estado" => Atom.to_string(m.estado)
    }
  end

  @doc """
  Reconstruye un mensaje a partir de un registro persistido.
  """
  @spec de_registro(map()) :: {:ok, Mensaje.t()} | {:error, motivo()}
  def de_registro(
        %{
          "id" => id,
          "fecha" => fecha,
          "remitente" => remitente,
          "destinatario" => destinatario,
          "contenido" => contenido
        } = registro
      )
      when is_binary(id) and is_binary(fecha) and is_binary(remitente) and
             is_binary(destinatario) and is_binary(contenido) do
    with {:ok, fecha} <- leer_fecha(fecha),
         {:ok, estado} <- interpretar_estado(Map.get(registro, "estado", "pendiente")) do
      {:ok,
       %Mensaje{
         id: id,
         fecha: fecha,
         remitente: remitente,
         destinatario: destinatario,
         contenido: contenido,
         estado: estado
       }}
    end
  end

  def de_registro(_registro), do: {:error, :registro_invalido}

  defp leer_fecha(texto) do
    case DateTime.from_iso8601(texto) do
      {:ok, fecha, _desfase} -> {:ok, fecha}
      {:error, _motivo} -> {:error, :fecha_invalida}
    end
  end

  # -- Validación y conversión -------------------------------------------------

  defp verificar_id_libre(mensajes, id) do
    if Map.has_key?(mensajes, id), do: {:error, :id_existente}, else: :ok
  end

  defp verificar_distintos(usuario, usuario), do: {:error, :destinatario_es_remitente}
  defp verificar_distintos(_remitente, _destinatario), do: :ok

  defp texto(valor, error) when is_binary(valor) do
    case String.trim(valor) do
      "" -> {:error, error}
      limpio -> {:ok, limpio}
    end
  end

  defp texto(_valor, error), do: {:error, error}

  defp interpretar_contenido(contenido) do
    with {:ok, limpio} <- texto(contenido, :contenido_invalido) do
      if String.length(limpio) <= @largo_maximo,
        do: {:ok, limpio},
        else: {:error, :contenido_demasiado_largo}
    end
  end

  defp interpretar_estado(estado) when estado in [:pendiente, :entregado], do: {:ok, estado}

  defp interpretar_estado(estado) when is_binary(estado) do
    case estado |> String.trim() |> String.downcase() do
      "pendiente" -> {:ok, :pendiente}
      "entregado" -> {:ok, :entregado}
      _ -> {:error, :estado_invalido}
    end
  end

  defp interpretar_estado(_estado), do: {:error, :estado_invalido}
end
