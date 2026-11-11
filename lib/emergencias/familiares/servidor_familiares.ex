defmodule Emergencias.Familiares.ServidorFamiliares do
  @moduledoc """
  Servidor concurrente basado en `GenServer` para las personas afectadas y los
  mensajes entre familiares.

  Es el único proceso dueño de los archivos de las entidades `:personas` y
  `:mensajes`, por lo que todas las modificaciones se ejecutan una a una, en el
  orden en que llegan los mensajes. Esto resuelve los conflictos concurrentes de
  la parte de familiares:

    * Si varias solicitudes simultáneas registran el mismo documento, la primera
      lo registra y las demás reciben `{:error, :documento_existente}`.
    * Si varias solicitudes simultáneas cierran el caso de la misma persona, solo
      la primera la reunifica; las demás reciben `{:error, :persona_reunificada}`.
    * Si varias solicitudes simultáneas entregan el mismo mensaje, solo la primera
      lo entrega; las demás reciben `{:error, :mensaje_entregado}`.
    * Los identificadores generados nunca se repiten, aunque los registros lleguen
      a la vez.

  La lógica de dominio reside en `Emergencias.Familiares.Personas` y
  `Emergencias.Familiares.Mensajes`; este módulo solo coordina el estado, la
  persistencia y la concurrencia.

  ## Persistencia

  Cada operación que modifica el estado reescribe el archivo de la entidad
  afectada. Si la escritura falla, el estado no cambia y la operación retorna
  `{:error, {:persistencia, motivo}}`. Al iniciar, el servidor carga ambos
  archivos; si alguno contiene un registro inválido, el proceso no arranca.

  ## Opciones de inicio

    * `:name`: nombre con el que se registra el proceso. Por defecto, el nombre del módulo.
    * `:entidad_personas`: nombre de la entidad de las personas. Por defecto, `:personas`.
    * `:entidad_mensajes`: nombre de la entidad de los mensajes. Por defecto, `:mensajes`.

  Todas las funciones de la API aceptan como último argumento opcional el servidor
  al que se dirigen, que por defecto es el registrado con el nombre del módulo.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  use GenServer

  alias Emergencias.Familiares.{Mensaje, Mensajes, Persona, Personas}
  alias Emergencias.Persistencia

  @entidad_personas :personas
  @entidad_mensajes :mensajes

  @typedoc "Proceso del servidor: su nombre registrado o su identificador."
  @type servidor :: GenServer.server()

  @typedoc "Motivo de un error de la API."
  @type motivo :: atom() | tuple()

  # -- API del cliente: personas -----------------------------------------------

  @doc """
  Inicia el servidor y carga las personas y los mensajes guardados.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opciones \\ []) do
    {entidad_personas, opciones} = Keyword.pop(opciones, :entidad_personas, @entidad_personas)
    {entidad_mensajes, opciones} = Keyword.pop(opciones, :entidad_mensajes, @entidad_mensajes)

    GenServer.start_link(
      __MODULE__,
      %{personas: entidad_personas, mensajes: entidad_mensajes},
      Keyword.put_new(opciones, :name, __MODULE__)
    )
  end

  @doc """
  Registra una persona nueva.

  Si `atributos` no incluye `:id`, el servidor genera el siguiente libre (`PE001`,
  `PE002`, etc.). Ver `Emergencias.Familiares.Personas.registrar/3` para los
  atributos y sus validaciones.
  """
  @spec registrar_persona(map(), servidor()) :: {:ok, Persona.t()} | {:error, motivo()}
  def registrar_persona(atributos, servidor \\ __MODULE__)

  def registrar_persona(atributos, servidor) when is_map(atributos),
    do: GenServer.call(servidor, {:registrar_persona, atributos})

  def registrar_persona(_atributos, _servidor), do: {:error, :atributos_invalidos}

  @doc """
  Retorna la persona con el identificador dado.
  """
  @spec obtener_persona(String.t(), servidor()) ::
          {:ok, Persona.t()} | {:error, motivo()}
  def obtener_persona(id, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:obtener_persona, id})

  @doc """
  Consulta las personas que cumplen todos los filtros (`:nombre`, `:documento`,
  `:zona` y `:estado`), ordenadas por identificador.
  """
  @spec consultar_personas(keyword(), servidor()) :: {:ok, [Persona.t()]} | {:error, motivo()}
  def consultar_personas(filtros \\ [], servidor \\ __MODULE__)

  def consultar_personas(filtros, servidor) when is_list(filtros),
    do: GenServer.call(servidor, {:consultar_personas, filtros})

  def consultar_personas(_filtros, _servidor), do: {:error, :filtros_invalidos}

  @doc """
  Cambia el estado de una persona y lo anota en su historial.

  Solo se aceptan las transiciones definidas en `Emergencias.Familiares.Personas`.
  """
  @spec cambiar_estado(String.t(), Persona.estado() | String.t(), servidor()) ::
          {:ok, Persona.t()} | {:error, motivo()}
  def cambiar_estado(id, nuevo_estado, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:cambiar_estado, id, nuevo_estado})

  # -- API del cliente: mensajes -----------------------------------------------

  @doc """
  Registra un mensaje nuevo en estado `:pendiente`.

  Si `atributos` no incluye `:id`, el servidor genera el siguiente libre (`ME001`,
  `ME002`, etc.). Ver `Emergencias.Familiares.Mensajes.enviar/3` para los atributos
  y sus validaciones.
  """
  @spec enviar_mensaje(map(), servidor()) :: {:ok, Mensaje.t()} | {:error, motivo()}
  def enviar_mensaje(atributos, servidor \\ __MODULE__)

  def enviar_mensaje(atributos, servidor) when is_map(atributos),
    do: GenServer.call(servidor, {:enviar_mensaje, atributos})

  def enviar_mensaje(_atributos, _servidor), do: {:error, :atributos_invalidos}

  @doc """
  Retorna el mensaje con el identificador dado.
  """
  @spec obtener_mensaje(String.t(), servidor()) :: {:ok, Mensaje.t()} | {:error, motivo()}
  def obtener_mensaje(id, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:obtener_mensaje, id})

  @doc """
  Consulta los mensajes que cumplen todos los filtros (`:remitente`, `:destinatario`,
  `:usuario` y `:estado`), ordenados por identificador.
  """
  @spec consultar_mensajes(keyword(), servidor()) :: {:ok, [Mensaje.t()]} | {:error, motivo()}
  def consultar_mensajes(filtros \\ [], servidor \\ __MODULE__)

  def consultar_mensajes(filtros, servidor) when is_list(filtros),
    do: GenServer.call(servidor, {:consultar_mensajes, filtros})

  def consultar_mensajes(_filtros, _servidor), do: {:error, :filtros_invalidos}

  @doc """
  Marca un mensaje como entregado. Un mensaje no puede entregarse dos veces.
  """
  @spec marcar_entregado(String.t(), servidor()) :: {:ok, Mensaje.t()} | {:error, motivo()}
  def marcar_entregado(id, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:marcar_entregado, id})

  @doc """
  Entrega todos los mensajes pendientes dirigidos a un destinatario.

  Retorna los mensajes entregados, ordenados por identificador; la lista es vacía
  si no había ninguno pendiente.
  """
  @spec entregar_pendientes(String.t(), servidor()) ::
          {:ok, [Mensaje.t()]} | {:error, motivo()}
  def entregar_pendientes(destinatario, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:entregar_pendientes, destinatario})

  # -- Callbacks del servidor --------------------------------------------------

  @impl true
  def init(entidades) do
    with {:ok, registros_personas} <- Persistencia.cargar(entidades.personas),
         {:ok, personas} <- cargar(registros_personas, &Personas.de_registro/1),
         {:ok, registros_mensajes} <- Persistencia.cargar(entidades.mensajes),
         {:ok, mensajes} <- cargar(registros_mensajes, &Mensajes.de_registro/1) do
      {:ok, %{entidades: entidades, personas: personas, mensajes: mensajes}}
    else
      {:error, motivo} -> {:stop, {:persistencia, motivo}}
    end
  end

  @impl true
  def handle_call({:registrar_persona, atributos}, _from, estado) do
    atributos = Map.put_new(atributos, :id, Personas.siguiente_id(estado.personas))
    aplicar(estado, :personas, Personas.registrar(estado.personas, atributos))
  end

  def handle_call({:obtener_persona, id}, _from, estado),
    do: {:reply, Personas.obtener(estado.personas, id), estado}

  def handle_call({:consultar_personas, filtros}, _from, estado),
    do: {:reply, Personas.consultar(estado.personas, filtros), estado}

  def handle_call({:cambiar_estado, id, nuevo_estado}, _from, estado),
    do: aplicar(estado, :personas, Personas.cambiar_estado(estado.personas, id, nuevo_estado))

  def handle_call({:enviar_mensaje, atributos}, _from, estado) do
    atributos = Map.put_new(atributos, :id, Mensajes.siguiente_id(estado.mensajes))
    aplicar(estado, :mensajes, Mensajes.enviar(estado.mensajes, atributos))
  end

  def handle_call({:obtener_mensaje, id}, _from, estado),
    do: {:reply, Mensajes.obtener(estado.mensajes, id), estado}

  def handle_call({:consultar_mensajes, filtros}, _from, estado),
    do: {:reply, Mensajes.consultar(estado.mensajes, filtros), estado}

  def handle_call({:marcar_entregado, id}, _from, estado),
    do: aplicar(estado, :mensajes, Mensajes.marcar_entregado(estado.mensajes, id))

  def handle_call({:entregar_pendientes, destinatario}, _from, estado),
    do: aplicar(estado, :mensajes, Mensajes.entregar_pendientes(estado.mensajes, destinatario))

  # -- Funciones privadas ------------------------------------------------------

  # Confirma el cambio solo si se pudo persistir; de lo contrario conserva el estado.
  defp aplicar(estado, coleccion, {:ok, nueva, valor}) do
    entidad = Map.fetch!(estado.entidades, coleccion)

    case persistir(entidad, nueva, conversor(coleccion)) do
      :ok -> {:reply, {:ok, valor}, Map.put(estado, coleccion, nueva)}
      {:error, motivo} -> {:reply, {:error, {:persistencia, motivo}}, estado}
    end
  end

  defp aplicar(estado, _coleccion, {:error, _motivo} = error), do: {:reply, error, estado}

  defp conversor(:personas), do: &Personas.a_registro/1
  defp conversor(:mensajes), do: &Mensajes.a_registro/1

  defp persistir(entidad, coleccion, a_registro) do
    registros =
      coleccion
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(a_registro)

    Persistencia.guardar(entidad, registros)
  end

  defp cargar(registros, de_registro) do
    Enum.reduce_while(registros, {:ok, %{}}, fn registro, {:ok, acumulado} ->
      case de_registro.(registro) do
        {:ok, elemento} -> {:cont, {:ok, Map.put(acumulado, elemento.id, elemento)}}
        {:error, _motivo} = error -> {:halt, error}
      end
    end)
  end
end
