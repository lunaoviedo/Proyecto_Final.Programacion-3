defmodule Emergencias.Recursos.ServidorAlbergues do
  @moduledoc """
  GenServer para gestionar la red de albergues.
  Controla de forma concurrente que la ocupación actual nunca supere
  la capacidad máxima establecida para cada refugio y persiste los datos.
  """
  use GenServer
  alias Emergencias.Recursos.Albergue
  alias Emergencias.Persistencia # Importamos el módulo de guardado

  # 1. API DEL CLIENTE

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def registrar_albergue(%Albergue{} = albergue) do
    # Ajustado a call para hacer match con el handle_call y recibir errores
    GenServer.call(__MODULE__, {:registrar, albergue})
  end

  def obtener_albergues() do
    GenServer.call(__MODULE__, :obtener_todos)
  end

  @doc """
  Registra el ingreso de una persona a un albergue por documento.
  Retorna {:ok, nueva_ocupacion} o {:error, motivo}.
  """
  # Ajustado para recibir el documento en texto en lugar de cantidad numérica
  def ingresar_persona(codigo, documento) when is_binary(documento) do
    GenServer.call(__MODULE__, {:ingresar, codigo, documento})
  end

  def registrar_salida(codigo, documento) when is_binary(documento) do
    GenServer.call(__MODULE__, {:salir, codigo, documento})
  end

  # 2. CALLBACKS DEL SERVIDOR

  @impl true
  def init(_estado_inicial) do
    # Al encender, leemos el archivo .jsonl y reconstruimos el mapa
    estado =
      case Persistencia.cargar(:albergues) do
        {:ok, registros} ->
          registros
          |> Enum.map(&Albergue.de_registro/1)
          |> Enum.into(%{}, fn albergue -> {albergue.codigo, albergue} end)

        {:error, _motivo} ->
          %{}
      end

    {:ok, estado}
  end

  @impl true
  def handle_call({:registrar, albergue}, _from, estado) do
    if Map.has_key?(estado, albergue.codigo) do
      {:reply, {:error, :albergue_ya_existe}, estado}
    else
      nuevo_estado = Map.put(estado, albergue.codigo, albergue)
      guardar_estado(nuevo_estado) # Guardamos en disco
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
            guardar_estado(nuevo_estado) # Guardamos en disco
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
          guardar_estado(nuevo_estado) # Guardamos en disco
          {:reply, {:ok, length(nueva_lista)}, nuevo_estado}
        else
          {:reply, {:error, :persona_no_encontrada}, estado}
        end
    end
  end

  # 3. FUNCIONES PRIVADAS DE PERSISTENCIA

  defp guardar_estado(estado) do
    registros =
      estado
      |> Map.values()
      |> Enum.map(&Albergue.a_registro/1)

    Persistencia.guardar(:albergues, registros)
  end
end
