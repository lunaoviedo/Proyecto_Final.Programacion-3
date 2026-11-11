defmodule Emergencias.Mascotas.ServidorMascotas do
  @moduledoc """
  Servidor concurrente basado en `GenServer` para los reportes de mascotas perdidas
  y encontradas.

  Es el único proceso dueño del archivo de la entidad `:mascotas`, por lo que todas
  las modificaciones se ejecutan una a una, en el orden en que llegan los mensajes.
  Esto resuelve el conflicto concurrente de que dos solicitudes simultáneas intenten
  cerrar el mismo reporte con parejas distintas: la primera lo resuelve y las demás
  reciben `{:error, :reporte_resuelto}`.

  La lógica de dominio reside en `Emergencias.Mascotas.Reportes` y el cálculo de
  similitud en `Emergencias.Mascotas.Coincidencias`; este módulo solo coordina el
  estado, la persistencia y la concurrencia.

  ## Persistencia

  Cada operación que modifica el estado reescribe el archivo de la entidad. Si la
  escritura falla, el estado no cambia y la operación retorna
  `{:error, {:persistencia, motivo}}`. Al iniciar, el servidor carga el archivo; si
  contiene un registro inválido, el proceso no arranca.

  ## Opciones de inicio

    * `:name`: nombre con el que se registra el proceso. Por defecto, el nombre del módulo.
    * `:entidad`: nombre de la entidad persistida. Por defecto, `:mascotas`.

  Todas las funciones de la API aceptan como último argumento opcional el servidor
  al que se dirigen, que por defecto es el registrado con el nombre del módulo.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  use GenServer

  alias Emergencias.Mascotas.{Coincidencias, Mascota, Reportes}
  alias Emergencias.Persistencia

  @entidad_por_defecto :mascotas

  @typedoc "Proceso del servidor: su nombre registrado o su identificador."
  @type servidor :: GenServer.server()

  @typedoc "Motivo de un error de la API."
  @type motivo :: Reportes.motivo()

  # -- API del cliente ---------------------------------------------------------

  @doc """
  Inicia el servidor y carga los reportes guardados.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opciones \\ []) do
    {entidad, opciones} = Keyword.pop(opciones, :entidad, @entidad_por_defecto)
    GenServer.start_link(__MODULE__, entidad, Keyword.put_new(opciones, :name, __MODULE__))
  end

  @doc """
  Registra un reporte nuevo en estado `:activa`.

  Si `atributos` no incluye `:id`, el servidor genera el siguiente libre (`MA001`,
  `MA002`, etc.). Ver `Emergencias.Mascotas.Reportes.registrar/2` para los atributos
  y sus validaciones.
  """
  @spec registrar(map(), servidor()) :: {:ok, Mascota.t()} | {:error, motivo()}
  def registrar(atributos, servidor \\ __MODULE__)

  def registrar(atributos, servidor) when is_map(atributos),
    do: GenServer.call(servidor, {:registrar, atributos})

  def registrar(_atributos, _servidor), do: {:error, :atributos_invalidos}

  @doc """
  Retorna el reporte con el identificador dado.
  """
  @spec obtener(String.t(), servidor()) :: {:ok, Mascota.t()} | {:error, motivo()}
  def obtener(id, servidor \\ __MODULE__), do: GenServer.call(servidor, {:obtener, id})

  @doc """
  Consulta los reportes que cumplen todos los filtros (`:especie`, `:zona`, `:estado`
  y `:tipo`), ordenados por identificador.
  """
  @spec consultar(keyword(), servidor()) :: {:ok, [Mascota.t()]} | {:error, motivo()}
  def consultar(filtros \\ [], servidor \\ __MODULE__)

  def consultar(filtros, servidor) when is_list(filtros),
    do: GenServer.call(servidor, {:consultar, filtros})

  def consultar(_filtros, _servidor), do: {:error, :filtros_invalidos}

  @doc """
  Busca las posibles coincidencias entre los reportes activos.

  El servidor solo entrega una copia de los reportes; el cálculo de similitud se
  realiza en el proceso que llama, de modo que una búsqueda extensa no bloquea al
  resto de operaciones.
  """
  @spec buscar_coincidencias(servidor()) :: [Coincidencias.coincidencia()]
  def buscar_coincidencias(servidor \\ __MODULE__) do
    servidor |> GenServer.call(:reportes) |> Coincidencias.buscar()
  end

  @doc """
  Marca dos reportes de tipo contrario como posible coincidencia.
  """
  @spec asociar(String.t(), String.t(), servidor()) ::
          {:ok, Reportes.pareja()} | {:error, motivo()}
  def asociar(id_a, id_b, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:asociar, id_a, id_b})

  @doc """
  Confirma la coincidencia entre dos reportes y cierra ambos.
  """
  @spec confirmar(String.t(), String.t(), servidor()) ::
          {:ok, Reportes.pareja()} | {:error, motivo()}
  def confirmar(id_a, id_b, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:confirmar, id_a, id_b})

  @doc """
  Descarta una posible coincidencia y devuelve ambos reportes al estado `:activa`.
  """
  @spec descartar(String.t(), servidor()) :: {:ok, Reportes.pareja()} | {:error, motivo()}
  def descartar(id, servidor \\ __MODULE__), do: GenServer.call(servidor, {:descartar, id})

  # -- Callbacks del servidor --------------------------------------------------

  @impl true
  def init(entidad) do
    with {:ok, registros} <- Persistencia.cargar(entidad),
         {:ok, reportes} <- cargar_reportes(registros) do
      {:ok, %{entidad: entidad, reportes: reportes}}
    else
      {:error, motivo} -> {:stop, {:persistencia, motivo}}
    end
  end

  @impl true
  def handle_call({:registrar, atributos}, _from, estado) do
    atributos = Map.put_new(atributos, :id, Reportes.siguiente_id(estado.reportes))
    aplicar(estado, Reportes.registrar(estado.reportes, atributos))
  end

  def handle_call({:obtener, id}, _from, estado),
    do: {:reply, Reportes.obtener(estado.reportes, id), estado}

  def handle_call({:consultar, filtros}, _from, estado),
    do: {:reply, Reportes.consultar(estado.reportes, filtros), estado}

  def handle_call(:reportes, _from, estado), do: {:reply, estado.reportes, estado}

  def handle_call({:asociar, id_a, id_b}, _from, estado),
    do: aplicar(estado, Reportes.asociar(estado.reportes, id_a, id_b))

  def handle_call({:confirmar, id_a, id_b}, _from, estado),
    do: aplicar(estado, Reportes.confirmar(estado.reportes, id_a, id_b))

  def handle_call({:descartar, id}, _from, estado),
    do: aplicar(estado, Reportes.descartar(estado.reportes, id))

  # -- Funciones privadas ------------------------------------------------------

  # Confirma el cambio solo si se pudo persistir; de lo contrario conserva el estado.
  defp aplicar(estado, {:ok, reportes, valor}) do
    case persistir(estado.entidad, reportes) do
      :ok -> {:reply, {:ok, valor}, %{estado | reportes: reportes}}
      {:error, motivo} -> {:reply, {:error, {:persistencia, motivo}}, estado}
    end
  end

  defp aplicar(estado, {:error, _motivo} = error), do: {:reply, error, estado}

  defp persistir(entidad, reportes) do
    registros =
      reportes
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&Reportes.a_registro/1)

    Persistencia.guardar(entidad, registros)
  end

  defp cargar_reportes(registros) do
    Enum.reduce_while(registros, {:ok, %{}}, fn registro, {:ok, acumulado} ->
      case Reportes.de_registro(registro) do
        {:ok, mascota} -> {:cont, {:ok, Map.put(acumulado, mascota.id, mascota)}}
        {:error, _motivo} = error -> {:halt, error}
      end
    end)
  end
end
