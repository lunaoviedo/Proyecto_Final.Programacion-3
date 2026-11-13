defmodule Emergencias.Recursos.ServidorInventario do
  use GenServer
  alias Emergencias.Recursos.{Recurso, Persistencia}

  # --- 1. API DEL CLIENTE ---
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{recursos: %{}, historial: []}, name: __MODULE__)
  end

  def registrar_recurso(%Recurso{} = recurso) do
    GenServer.call(__MODULE__, {:registrar, recurso})
  end

  def descontar_recurso(codigo, cantidad) do
    GenServer.call(__MODULE__, {:descontar, codigo, cantidad})
  end

  # Modificado: transfer_resource ahora maneja origen, destino y cantidad real
  def transferir_recurso(codigo_origen, codigo_destino, cantidad) do
    GenServer.call(__MODULE__, {:transferir, codigo_origen, codigo_destino, cantidad})
  end

  def listar_recursos(filtros \\ %{}) do
    GenServer.call(__MODULE__, {:listar, filtros})
  end

  # Nuevo: Función para reportar los critical_resources
  def recursos_criticos(umbral \\ 10) do
    GenServer.call(__MODULE__, {:criticos, umbral})
  end

  def obtener_historial_movimientos() do
    GenServer.call(__MODULE__, :obtener_historial)
  end

  # --- 2. CALLBACKS DEL SERVIDOR ---
  @impl true
  def init(_opts) do
    recursos = case Persistencia.cargar(:recursos) do
      {:ok, regs} -> Enum.reduce(regs, %{}, fn r, acc -> Map.put(acc, r["codigo"], Recurso.de_registro(r)) end)
      _ -> %{}
    end

    historial = case Persistencia.cargar(:historial_inventario) do
      {:ok, hist} -> hist
      _ -> []
    end

    {:ok, %{recursos: recursos, historial: historial}}
  end

  @impl true
  def handle_call({:registrar, recurso}, _from, estado) do
    if Map.has_key?(estado.recursos, recurso.codigo) do
      {:reply, {:error, :recurso_ya_existe}, estado}
    else
      nuevos_recursos = Map.put(estado.recursos, recurso.codigo, recurso)
      # Registramos la ENTRADA en el historial
      nuevo_historial = registrar_movimiento(estado.historial, "ENTRADA", recurso.codigo, recurso.cantidad, "Proveedor", recurso.ubicacion)

      nuevo_estado = %{recursos: nuevos_recursos, historial: nuevo_historial}
      guardar_estado(nuevo_estado)

      {:reply, :ok, nuevo_estado}
    end
  end

  @impl true
  def handle_call({:descontar, codigo, cantidad}, _from, estado) do
    case Map.get(estado.recursos, codigo) do
      nil -> {:reply, {:error, :recurso_no_encontrado}, estado}
      recurso ->
        if recurso.cantidad >= cantidad do
          recurso_actualizado = %{recurso | cantidad: recurso.cantidad - cantidad}
          nuevos_recursos = Map.put(estado.recursos, codigo, recurso_actualizado)
          # Registramos la SALIDA
          nuevo_historial = registrar_movimiento(estado.historial, "SALIDA", codigo, cantidad, recurso.ubicacion, "Asignación a Necesidad")

          nuevo_estado = %{recursos: nuevos_recursos, historial: nuevo_historial}
          guardar_estado(nuevo_estado)

          {:reply, :ok, nuevo_estado}
        else
          {:reply, {:error, :stock_insuficiente}, estado}
        end
    end
  end

  @impl true
  def handle_call({:transferir, codigo_origen, codigo_destino, cantidad}, _from, estado) do
    origen = Map.get(estado.recursos, codigo_origen)
    destino = Map.get(estado.recursos, codigo_destino)

    cond do
      is_nil(origen) -> {:reply, {:error, :origen_no_encontrado}, estado}
      is_nil(destino) -> {:reply, {:error, :destino_no_encontrado}, estado}
      origen.cantidad < cantidad -> {:reply, {:error, :stock_insuficiente}, estado}
      true ->
        # Restamos del origen y sumamos al destino
        origen_act = %{origen | cantidad: origen.cantidad - cantidad}
        destino_act = %{destino | cantidad: destino.cantidad + cantidad}

        nuevos_recursos = estado.recursos
                          |> Map.put(codigo_origen, origen_act)
                          |> Map.put(codigo_destino, destino_act)

        nuevo_historial = registrar_movimiento(estado.historial, "TRANSFERENCIA", "#{codigo_origen}->#{codigo_destino}", cantidad, origen.ubicacion, destino.ubicacion)

        nuevo_estado = %{recursos: nuevos_recursos, historial: nuevo_historial}
        guardar_estado(nuevo_estado)

        {:reply, :ok, nuevo_estado}
    end
  end

  @impl true
  def handle_call({:listar, filtros}, _from, estado) do
    lista = estado.recursos
            |> Map.values()
            |> aplicar_filtros(filtros)
    {:reply, lista, estado}
  end

  @impl true
  def handle_call({:criticos, umbral}, _from, estado) do
    criticos = estado.recursos
               |> Map.values()
               |> Enum.filter(&(&1.cantidad <= umbral))
    {:reply, criticos, estado}
  end

  @impl true
  def handle_call(:obtener_historial, _from, estado) do
    {:reply, estado.historial, estado}
  end

  # --- 3. FUNCIONES PRIVADAS ---
  defp guardar_estado(estado) do
    registros = estado.recursos |> Map.values() |> Enum.map(&Recurso.a_registro/1)
    Persistencia.guardar(:recursos, registros)
    Persistencia.guardar(:historial_inventario, estado.historial)
  end

  defp registrar_movimiento(historial, accion, codigo, cantidad, origen, destino) do
    movimiento = %{
      "fecha" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "accion" => accion,
      "codigo_recurso" => codigo,
      "cantidad" => cantidad,
      "origen" => origen,
      "destino" => destino
    }
    # Guardamos al inicio de la lista para que los más recientes salgan primero
    [movimiento | historial]
  end

  defp aplicar_filtros(lista, filtros) when map_size(filtros) == 0, do: lista
  defp aplicar_filtros(lista, filtros) do
    Enum.filter(lista, fn recurso ->
      Enum.all?(filtros, fn {clave, valor} ->
        case clave do
          :tipo -> String.downcase(recurso.categoria) == String.downcase(valor)
          :zona -> String.downcase(recurso.ubicacion) == String.downcase(valor)
          _ -> true
        end
      end)
    end)
  end
end
