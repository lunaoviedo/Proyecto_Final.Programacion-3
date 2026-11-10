defmodule Emergencias.Recursos.ServidorInventario do
  @moduledoc """
  GenServer encargado de gestionar el inventario global de recursos.
  Garantiza la concurrencia procesando las solicitudes una por una,
  evitando inconsistencias en las cantidades asignadas.
  """
  use GenServer
  alias Emergencias.Recursos.Recurso

  # 1. API DEL CLIENTE (Lo que llaman otros módulos)

  @doc """
  Inicia el servidor de inventario.
  """
  def start_link(_opts \\ []) do
    # Iniciamos el proceso y le damos el mismo nombre del módulo para encontrarlo fácil
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Agrega un nuevo recurso al inventario. (Asíncrono - No espera respuesta)
  """
  def registrar_recurso(%Recurso{} = recurso) do
    GenServer.cast(__MODULE__, {:registrar, recurso})
  end

  @doc """
  Obtiene la lista de todos los recursos disponibles. (Síncrono - Espera respuesta)
  """
  def obtener_inventario() do
    GenServer.call(__MODULE__, :obtener_todos)
  end

  # 2. CALLBACKS DEL SERVIDOR (Lo que ejecuta el proceso internamente)

  @impl true
  def init(estado_inicial) do
    # El estado interno del servidor será un Mapa %{}
    # Las llaves serán los códigos (ej. "R001") y los valores la estructura Recurso
    {:ok, estado_inicial}
  end

  # handle_cast maneja mensajes asíncronos (no devolvemos respuesta al cliente)
  @impl true
  def handle_cast({:registrar, recurso}, estado) do
    # Map.put inserta o actualiza el recurso en nuestro diccionario/mapa de estado
    nuevo_estado = Map.put(estado, recurso.codigo, recurso)

    # Retornamos {:noreply, nuevo_estado} para decirle al GenServer que actualice su memoria
    {:noreply, nuevo_estado}
  end

  # handle_call maneja mensajes síncronos (el cliente se queda esperando la respuesta)
  @impl true
  def handle_call(:obtener_todos, _from, estado) do
    # Map.values extrae solo los recursos (ignorando las llaves del mapa) y los devuelve como lista
    lista_recursos = Map.values(estado)

    # Retornamos {:reply, respuesta_para_el_cliente, estado_intacto}
    {:reply, lista_recursos, estado}
  end
end
