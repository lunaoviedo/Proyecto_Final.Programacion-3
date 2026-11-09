defmodule Emergencias.Zonas.ServidorZonas do

  use GenServer

  alias Emergencias.Persistencia
  alias Emergencias.Zonas.Catalogo


  def start_link(opciones \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opciones, :name, __MODULE__))
  end

  def registrar_zona(codigo, nombre, nivel, afectados \\ 0),
    do: GenServer.call(__MODULE__, {:registrar_zona, codigo, nombre, nivel, afectados})

  def registrar_sector(codigo_zona, codigo, nombre, afectados \\ 0),
    do: GenServer.call(__MODULE__, {:registrar_sector, codigo_zona, codigo, nombre, afectados})

  def registrar_punto(codigo_sector, codigo, nombre, afectados \\ 0),
    do: GenServer.call(__MODULE__, {:registrar_punto, codigo_sector, codigo, nombre, afectados})

  def obtener_zona(codigo), do: GenServer.call(__MODULE__, {:obtener_zona, codigo})
  def estado_zona(codigo), do: GenServer.call(__MODULE__, {:estado_zona, codigo})
  def listar_zonas, do: GenServer.call(__MODULE__, :listar_zonas)


  @impl true
  def init(:ok) do
    with {:ok, registros} <- Persistencia.cargar(:zonas),
         {:ok, zonas} <- cargar_zonas(registros) do
      {:ok, zonas}
    else
      {:error, motivo} -> {:stop, {:persistencia, motivo}}
    end
  end

  @impl true
  def handle_call({:registrar_zona, codigo, nombre, nivel, afectados}, _from, zonas),
    do: confirmar(Catalogo.registrar_zona(zonas, codigo, nombre, nivel, afectados), zonas)

  def handle_call({:registrar_sector, codigo_zona, codigo, nombre, afectados}, _from, zonas),
    do: confirmar(Catalogo.registrar_sector(zonas, codigo_zona, codigo, nombre, afectados), zonas)

  def handle_call({:registrar_punto, codigo_sector, codigo, nombre, afectados}, _from, zonas),
    do: confirmar(Catalogo.registrar_punto(zonas, codigo_sector, codigo, nombre, afectados), zonas)

  def handle_call({:obtener_zona, codigo}, _from, zonas),
    do: {:reply, Catalogo.obtener_zona(zonas, codigo), zonas}

  def handle_call({:estado_zona, codigo}, _from, zonas) do
    respuesta =
      with {:ok, zona} <- Catalogo.obtener_zona(zonas, codigo), do: {:ok, Catalogo.resumen(zona)}

    {:reply, respuesta, zonas}
  end

  def handle_call(:listar_zonas, _from, zonas),
    do: {:reply, Map.values(zonas), zonas}


  defp confirmar({:ok, nuevas_zonas, valor}, zonas) do
    case persistir(nuevas_zonas) do
      :ok -> {:reply, {:ok, valor}, nuevas_zonas}
      {:error, motivo} -> {:reply, {:error, {:persistencia, motivo}}, zonas}
    end
  end

  defp confirmar({:error, _} = error, zonas), do: {:reply, error, zonas}

  defp persistir(zonas) do
    Persistencia.guardar(:zonas, zonas |> Map.values() |> Enum.map(&Catalogo.a_registro/1))
  end

  defp cargar_zonas(registros) do
    Enum.reduce_while(registros, {:ok, %{}}, fn registro, {:ok, acumulado} ->
      case Catalogo.de_registro(registro) do
        {:ok, zona} -> {:cont, {:ok, Map.put(acumulado, zona.codigo, zona)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
