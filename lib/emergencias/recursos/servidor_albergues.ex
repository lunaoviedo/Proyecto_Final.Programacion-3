defmodule Emergencias.Recursos.ServidorAlbergues do
  @moduledoc """
  GenServer para gestionar la red de albergues.
  Controla de forma concurrente que la ocupación actual nunca supere
  la capacidad máxima establecida para cada refugio.
  """
  use GenServer
  alias Emergencias.Recursos.Albergue

  # 1. API DEL CLIENTE

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def registrar_albergue(%Albergue{} = albergue) do
    GenServer.cast(__MODULE__, {:registrar, albergue})
  end

  def obtener_albergues() do
    GenServer.call(__MODULE__, :obtener_todos)
  end

  @doc """
  Registra el ingreso de un grupo de personas a un albergue específico.
  Retorna {:ok, nueva_ocupacion} o {:error, :capacidad_excedida}.
  """
  def ingresar_personas(codigo, cantidad) when is_integer(cantidad) and cantidad > 0 do
    GenServer.call(__MODULE__, {:ingresar, codigo, cantidad})
  end

  # 2. CALLBACKS DEL SERVIDOR

  @impl true
  def init(estado_inicial) do
    {:ok, estado_inicial}
  end

  @impl true
  def handle_cast({:registrar, albergue}, estado) do
    nuevo_estado = Map.put(estado, albergue.codigo, albergue)
    {:noreply, nuevo_estado}
  end

  @impl true
  def handle_call(:obtener_todos, _from, estado) do
    {:reply, Map.values(estado), estado}
  end

  @impl true
  def handle_call({:ingresar, codigo, cantidad}, _from, estado) do
    case Map.get(estado, codigo) do
      nil ->
        {:reply, {:error, :albergue_no_encontrado}, estado}

      albergue ->
        nueva_ocupacion = albergue.ocupacion_actual + cantidad

        # Validamos que el ingreso no supere el límite del albergue
        if nueva_ocupacion <= albergue.capacidad_maxima do
          albergue_actualizado = %{albergue | ocupacion_actual: nueva_ocupacion}
          nuevo_estado = Map.put(estado, codigo, albergue_actualizado)

          {:reply, {:ok, albergue_actualizado.ocupacion_actual}, nuevo_estado}
        else
          # Rechazamos la petición para evitar el sobrecupo
          {:reply, {:error, :capacidad_excedida}, estado}
        end
    end
  end
end
