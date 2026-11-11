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
  def handle_call({:registrar, albergue}, _from, estado) do
    if Map.has_key?(estado, albergue.codigo) do
      {:reply, {:error, :albergue_ya_existe}, estado}
    else
      nuevo_estado = Map.put(estado, albergue.codigo, albergue)
      {:reply, :ok, nuevo_estado}
    end
  end

  @impl true
  def handle_call(:obtener_todos, _from, estado) do
    {:reply, Map.values(estado), estado}
  end

  @impl true
  def handle_call({:ingresar, codigo, documento}, _from, estado) do
    case Map.get(estado, codigo) do
      nil ->
        {:reply, {:error, :albergue_no_encontrado}, estado}

      albergue ->
        if documento in albergue.ocupacion do
          {:reply, {:error, :persona_ya_ingresada}, estado}
        else
          nueva_ocupacion = length(albergue.ocupacion) + 1

          if nueva_ocupacion <= albergue.capacidad_maxima do
            albergue_actualizado = %{albergue | ocupacion: [documento | albergue.ocupacion]}
            nuevo_estado = Map.put(estado, codigo, albergue_actualizado)
            {:reply, {:ok, nueva_ocupacion}, nuevo_estado}
          else
            {:reply, {:error, :capacidad_excedida}, estado}
          end
        end
    end
  end

  @impl true
  def handle_call({:salir, codigo, documento}, _from, estado) do
    case Map.get(estado, codigo) do
      nil ->
        {:reply, {:error, :albergue_no_encontrado}, estado}

      albergue ->
        if documento in albergue.ocupacion do
          nueva_lista = List.delete(albergue.ocupacion, documento)
          albergue_actualizado = %{albergue | ocupacion: nueva_lista}
          nuevo_estado = Map.put(estado, codigo, albergue_actualizado)
          {:reply, {:ok, length(nueva_lista)}, nuevo_estado}
        else
          {:reply, {:error, :persona_no_encontrada}, estado}
        end
    end
  end
end
