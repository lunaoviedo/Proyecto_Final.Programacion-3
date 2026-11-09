defmodule Emergencias.Zonas.ServidorZonas do
  @moduledoc """
  Servidor concurrente basado en `GenServer` para administrar el catálogo de zonas,
  sectores, puntos y su persistencia automática.

  ##informacion del proyecto
  - autor: Simon Lopez E, Luna Sofia Oviedo Rios, David Alejandro Henao Jaramillo
  - fecha: noviembre del 2026
  - licencia: GNU GPL v3
  """

  use GenServer

  alias Emergencias.Persistencia
  alias Emergencias.Zonas.Catalogo


  @doc """
  Inicia el proceso del `GenServer` para la gestión de zonas.
  """
  def start_link(opciones \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opciones, :name, __MODULE__))
  end

  @doc """
  Registra una zona de manera síncrona en el servidor.
  """
  def registrar_zona(codigo, nombre, nivel, afectados \\ 0),
    do: GenServer.call(__MODULE__, {:registrar_zona, codigo, nombre, nivel, afectados})

  @doc """
  Registra un sector vinculado a una zona específica a través del servidor.
  """
  def registrar_sector(codigo_zona, codigo, nombre, afectados \\ 0),
    do: GenServer.call(__MODULE__, {:registrar_sector, codigo_zona, codigo, nombre, afectados})

  @doc """
  Registra un punto dentro de un sector específico mediante el servidor.
  """
  def registrar_punto(codigo_sector, codigo, nombre, afectados \\ 0),
    do: GenServer.call(__MODULE__, {:registrar_punto, codigo_sector, codigo, nombre, afectados})

  @doc """
  Obtiene la información de una zona a partir de su código.
  """
  def obtener_zona(codigo), do: GenServer.call(__MODULE__, {:obtener_zona, codigo})

  @doc """
  Obtiene un resumen detallado y estadístico del estado de una zona.
  """
  def estado_zona(codigo), do: GenServer.call(__MODULE__, {:estado_zona, codigo})

  @doc """
  Lista todas las zonas registradas en el sistema.
  """
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
