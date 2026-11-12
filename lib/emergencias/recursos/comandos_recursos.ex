defmodule Emergencias.Recursos.ServidorNecesidades do
  use GenServer
  alias Emergencias.Recursos.{Necesidad, Persistencia}

  # --- 1. API DEL CLIENTE ---
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def registrar_necesidad(%Necesidad{} = necesidad) do
    GenServer.call(__MODULE__, {:registrar, necesidad})
  end

  def cambiar_estado(id, nuevo_estado) do
    GenServer.call(__MODULE__, {:cambiar_estado, id, nuevo_estado})
  end

  def obtener_necesidad(id) do
    GenServer.call(__MODULE__, {:obtener, id})
  end

  # Los filtros son un mapa opcional, ej: %{estado: :pendiente, zona: "Norte"}
  def listar_necesidades(filtros \\ %{}) do
    GenServer.call(__MODULE__, {:listar, filtros})
  end

  # --- 2. CALLBACKS DEL SERVIDOR ---
  @impl true
  def init(_estado_inicial) do
    case Persistencia.cargar(:necesidades) do
      {:ok, registros} ->
        estado =
          Enum.reduce(registros, %{}, fn reg, acc ->
            necesidad = Necesidad.de_registro(reg)
            Map.put(acc, necesidad.id, necesidad)
          end)
        {:ok, estado}
      _ ->
        {:ok, %{}}
    end
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
  def handle_call({:obtener, id}, _from, estado) do
    case Map.get(estado, id) do
      nil -> {:reply, {:error, :no_encontrada}, estado}
      necesidad -> {:reply, {:ok, necesidad}, estado}
    end
  end

  @impl true
  def handle_call({:cambiar_estado, id, nuevo_estado}, _from, estado) do
    case Map.get(estado, id) do
      nil ->
        {:reply, {:error, :no_encontrada}, estado}

      necesidad ->
        if transicion_valida?(necesidad.estado, nuevo_estado) do
          necesidad_actualizada = %{necesidad | estado: nuevo_estado}
          nuevo_estado_mapa = Map.put(estado, id, necesidad_actualizada)
          guardar_estado(nuevo_estado_mapa)
          {:reply, :ok, nuevo_estado_mapa}
        else
          {:reply, {:error, :transicion_invalida}, estado}
        end
    end
  end

  @impl true
  def handle_call({:listar, filtros}, _from, estado) do
    lista =
      estado
      |> Map.values()
      |> aplicar_filtros(filtros)
      # Ordenamos por prioridad (asumiendo que 1 es la prioridad más alta/urgente)
      |> Enum.sort_by(& &1.prioridad, :asc)

    {:reply, lista, estado}
  end

  # --- 3. FUNCIONES PRIVADAS ---
  defp guardar_estado(estado) do
    registros =
      estado
      |> Map.values()
      |> Enum.map(&Necesidad.a_registro/1)

    # Persistencia segura como pide el documento
    Persistencia.guardar(:necesidades, registros)
  end

  # MÁQUINA DE ESTADOS: Reglas estrictas de transición
  defp transicion_valida?(actual, nuevo) when actual == nuevo, do: true
  defp transicion_valida?(:pendiente, :evaluada), do: true
  defp transicion_valida?(:pendiente, :cancelada), do: true
  defp transicion_valida?(:evaluada, :asignada), do: true
  defp transicion_valida?(:evaluada, :cancelada), do: true
  defp transicion_valida?(:asignada, :atendida), do: true
  defp transicion_valida?(:asignada, :cancelada), do: true
  # Cualquier otro salto (ej. de pendiente a atendida directamente) se bloquea
  defp transicion_valida?(_, _), do: false

  # APLICACIÓN DE FILTROS DINÁMICOS
  defp aplicar_filtros(lista, filtros) when map_size(filtros) == 0, do: lista
  defp aplicar_filtros(lista, filtros) do
    Enum.filter(lista, fn necesidad ->
      Enum.all?(filtros, fn {clave, valor} ->
        case clave do
          :zona -> necesidad.zona == valor
          :tipo -> necesidad.tipo == valor
          :prioridad -> necesidad.prioridad == String.to_integer(valor)
          :estado -> necesidad.estado == valor
          _ -> true
        end
      end)
    end)
  end
end
