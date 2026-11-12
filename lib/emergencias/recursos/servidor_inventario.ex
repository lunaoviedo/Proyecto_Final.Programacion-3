defmodule Emergencias.Recursos.ServidorInventario do
  @moduledoc """
  GenServer encargado de gestionar el inventario global de recursos.
  Garantiza la concurrencia procesando las solicitudes una por una,
  evitando inconsistencias en las cantidades asignadas y persistiendo datos.
  """
  use GenServer
  alias Emergencias.Recursos.Recurso
  alias Emergencias.Persistencia # Importamos el módulo de persistencia

  # 1. API DEL CLIENTE

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def registrar_recurso(%Recurso{} = recurso) do
    GenServer.call(__MODULE__, {:registrar, recurso})
  end

  def obtener_inventario() do
    GenServer.call(__MODULE__, :obtener_todos)
  end

  def transferir_recurso(codigo, nueva_ubicacion) do
    GenServer.call(__MODULE__, {:transferir, codigo, nueva_ubicacion})
  end

  def obtener_historial_movimientos() do
    # Leemos directamente del archivo de bitácora
    case Persistencia.cargar(:movimientos) do
      {:ok, registros} -> registros
      _ -> []
    end
  end

  @doc """
  Intenta descontar una cantidad específica de un recurso.
  Retorna {:ok, cantidad_restante} si hay éxito, o {:error, razon} si falla.
  """
  def asignar_recurso(codigo, cantidad_requerida)
      when is_integer(cantidad_requerida) and cantidad_requerida > 0 do
    GenServer.call(__MODULE__, {:asignar, codigo, cantidad_requerida})
  end

  # 2. CALLBACKS DEL SERVIDOR

  @impl true
  def init(_estado_inicial) do
    # Al arrancar, cargamos el inventario desde el disco
    estado =
      case Persistencia.cargar(:recursos) do
        {:ok, registros} ->
          registros
          |> Enum.map(&Recurso.de_registro/1)
          |> Enum.into(%{}, fn recurso -> {recurso.codigo, recurso} end)

        {:error, _motivo} ->
          %{}
      end

    {:ok, estado}
  end

  @impl true
  def handle_call({:registrar, recurso}, _from, estado) do
    if Map.has_key?(estado, recurso.codigo) do
      {:reply, {:error, :recurso_ya_existe}, estado}
    else
      nuevo_estado = Map.put(estado, recurso.codigo, recurso)
      guardar_estado(nuevo_estado) # Sincronizamos la RAM con el disco
      {:reply, :ok, nuevo_estado}
    end
  end

  @impl true
  def handle_call(:obtener_todos, _from, estado) do
    lista_recursos = Map.values(estado)
    {:reply, lista_recursos, estado}
  end

  @impl true
  def handle_call({:asignar, codigo, cantidad_requerida}, _from, estado) do
    case Map.get(estado, codigo) do
      nil ->
        {:reply, {:error, :recurso_no_encontrado}, estado}

      recurso ->
        if recurso.cantidad >= cantidad_requerida do
          recurso_actualizado = %{recurso | cantidad: recurso.cantidad - cantidad_requerida}
          nuevo_estado = Map.put(estado, codigo, recurso_actualizado)

          guardar_estado(nuevo_estado) # Sincronizamos el descuento con el disco

          {:reply, {:ok, recurso_actualizado.cantidad}, nuevo_estado}
        else
          {:reply, {:error, :inventario_insuficiente}, estado}
        end
    end
  end

  @impl true
  def handle_call({:transferir, codigo, nueva_ubicacion}, _from, estado) do
    case Map.get(estado, codigo) do
      nil ->
        {:reply, {:error, :recurso_no_encontrado}, estado}

      recurso ->
        ubicacion_anterior = recurso.ubicacion
        recurso_actualizado = %{recurso | ubicacion: nueva_ubicacion}
        nuevo_estado = Map.put(estado, codigo, recurso_actualizado)

        # Guardamos el inventario actualizado
        guardar_estado(nuevo_estado)

        # Registramos el movimiento en el historial (archivo append-only)
        movimiento = %{
          "fecha" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_string(),
          "accion" => "Transferencia",
          "codigo_recurso" => codigo,
          "origen" => ubicacion_anterior,
          "destino" => nueva_ubicacion
        }
        Persistencia.agregar(:movimientos, movimiento)

        {:reply, :ok, nuevo_estado}
    end
  end

  # 3. FUNCIONES PRIVADAS DE PERSISTENCIA

  defp guardar_estado(estado) do
    registros =
      estado
      |> Map.values()
      |> Enum.map(&Recurso.a_registro/1)

    Persistencia.guardar(:recursos, registros)
  end
end
