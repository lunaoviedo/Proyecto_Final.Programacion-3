defmodule Emergencias.Recursos.ServidorNecesidades do
  @moduledoc """
  GenServer para gestionar el registro y consulta de las necesidades de los albergues.
  """
  use GenServer
  alias Emergencias.Recursos.Necesidad
  alias Emergencias.Persistencia

  # --- API DEL CLIENTE ---

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def registrar_necesidad(%Necesidad{} = necesidad) do
    GenServer.call(__MODULE__, {:registrar, necesidad})
  end

  def listar_necesidades() do
    GenServer.call(__MODULE__, :listar_todas)
  end

  def listar_pendientes() do
    GenServer.call(__MODULE__, :listar_pendientes)
  end

  def satisfacer_necesidad(id) do
    GenServer.call(__MODULE__, {:satisfacer, id})
  end

  # --- CALLBACKS DEL SERVIDOR ---

  @impl true
  def init(_opts) do
    estado =
      case Persistencia.cargar(:necesidades) do
        {:ok, registros} ->
          registros
          |> Enum.map(&Necesidad.de_registro/1)
          |> Enum.into(%{}, fn n -> {n.id, n} end)

        {:error, _motivo} ->
          %{}
      end

    {:ok, estado}
  end

  @impl true
  def handle_call({:registrar, necesidad}, _from, estado) do
    if Map.has_key?(estado, necesidad.id) do
      {:reply, {:error, :necesidad_ya_existe}, estado}
    else
      nuevo_estado = Map.put(estado, necesidad.id, necesidad)
      guardar_estado(nuevo_estado)
      {:reply, :ok, nuevo_estado}
    end
  end

  @impl true
  def handle_call(:listar_todas, _from, estado) do
    {:reply, Map.values(estado), estado}
  end

  @impl true
  def handle_call(:listar_pendientes, _from, estado) do
    # Filtramos la lista de memoria para devolver solo las que tienen estado :pendiente
    pendientes =
      estado
      |> Map.values()
      |> Enum.filter(fn n -> n.estado == :pendiente end)

    {:reply, pendientes, estado}
  end

  @impl true
  def handle_call({:satisfacer, id}, _from, estado) do
    case Map.get(estado, id) do
      nil ->
        {:reply, {:error, :necesidad_no_encontrada}, estado}

      necesidad ->
        actualizada = %{necesidad | estado: :satisfecha}
        nuevo_estado = Map.put(estado, id, actualizada)
        guardar_estado(nuevo_estado)
        {:reply, :ok, nuevo_estado}
    end
  end

  # --- FUNCIONES PRIVADAS ---

  defp guardar_estado(estado) do
    registros =
      estado
      |> Map.values()
      |> Enum.map(&Necesidad.a_registro/1)

    Persistencia.guardar(:necesidades, registros)
  end
end
