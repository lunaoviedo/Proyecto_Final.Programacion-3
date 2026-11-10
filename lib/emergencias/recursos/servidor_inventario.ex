defmodule Emergencias.Recursos.ServidorInventario do
  @moduledoc """
  GenServer encargado de gestionar el inventario global de recursos.
  Garantiza la concurrencia procesando las solicitudes una por una,
  evitando inconsistencias en las cantidades asignadas.
  """
  use GenServer
  alias Emergencias.Recursos.Recurso

  # 1. API DEL CLIENTE

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def registrar_recurso(%Recurso{} = recurso) do
    GenServer.cast(__MODULE__, {:registrar, recurso})
  end

  def obtener_inventario() do
    GenServer.call(__MODULE__, :obtener_todos)
  end

  @doc """
  Intenta descontar una cantidad específica de un recurso.
  Retorna {:ok, cantidad_restante} si hay éxito, o {:error, razon} si falla.
  """
  # Usamos 'when' (guarda) para asegurar que no nos pidan números negativos o cero
  def asignar_recurso(codigo, cantidad_requerida)
      when is_integer(cantidad_requerida) and cantidad_requerida > 0 do
    GenServer.call(__MODULE__, {:asignar, codigo, cantidad_requerida})
  end

  # 2. CALLBACKS DEL SERVIDOR

  @impl true
  def init(estado_inicial) do
    {:ok, estado_inicial}
  end

  @impl true
  def handle_cast({:registrar, recurso}, estado) do
    nuevo_estado = Map.put(estado, recurso.codigo, recurso)
    {:noreply, nuevo_estado}
  end

  @impl true
  def handle_call(:obtener_todos, _from, estado) do
    lista_recursos = Map.values(estado)
    {:reply, lista_recursos, estado}
  end

  # Nuevo callback para manejar la asignación de recursos
  @impl true
  def handle_call({:asignar, codigo, cantidad_requerida}, _from, estado) do
    # Map.get busca en nuestro estado usando el código (ej: "R001")
    case Map.get(estado, codigo) do
      nil ->
        # El recurso no existe en el inventario. Devolvemos un error en forma de tupla.
        # No modificamos el estado.
        {:reply, {:error, :recurso_no_encontrado}, estado}

      recurso ->
        # El recurso existe. Ahora validamos si hay suficiente cantidad.
        if recurso.cantidad >= cantidad_requerida do
          # Sintaxis de actualización de un Struct: %{variable | clave: nuevo_valor}
          recurso_actualizado = %{recurso | cantidad: recurso.cantidad - cantidad_requerida}

          # Guardamos el recurso actualizado en el estado
          nuevo_estado = Map.put(estado, codigo, recurso_actualizado)

          # Respondemos con éxito y el nuevo estado
          {:reply, {:ok, recurso_actualizado.cantidad}, nuevo_estado}
        else
          # Hay recurso, pero no alcanza la cantidad. Devolvemos error.
          # Esto evita el problema de concurrencia y los inventarios negativos.
          {:reply, {:error, :inventario_insuficiente}, estado}
        end
    end
  end
end
