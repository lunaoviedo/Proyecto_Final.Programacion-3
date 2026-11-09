defmodule Emergencias.Usuarios.ServidorSesiones do
  use GenServer

  alias Emergencias.Persistencia
  alias Emergencias.Usuarios.Cuentas

  def start_link(opciones \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opciones, :name, __MODULE__))
  end

  def conectar(usuario, clave, rol, zona),
    do: GenServer.call(__MODULE__, {:conectar, usuario, clave, rol, zona})

  def desconectar(usuario), do: GenServer.call(__MODULE__, {:desconectar, usuario})

  def conectado?(usuario), do: GenServer.call(__MODULE__, {:conectado?, usuario})

  def autorizar(usuario, accion), do: GenServer.call(__MODULE__, {:autorizar, usuario, accion})

  def obtener_usuario(usuario), do: GenServer.call(__MODULE__, {:obtener_usuario, usuario})

  def registrar_actividad(usuario, accion),
    do: GenServer.call(__MODULE__, {:registrar_actividad, usuario, accion})

  @impl true
  def init(:ok) do
    with {:ok, registros} <- Persistencia.cargar(:usuarios),
         {:ok, usuarios} <- cargar_usuarios(registros) do
      {:ok, %{usuarios: usuarios, sesiones: MapSet.new()}}
    else
      {:error, motivo} -> {:stop, {:persistencia, motivo}}
    end
  end

  @impl true
  def handle_call({:registrar_actividad, usuario, accion}, _from, estado) do
  with {:ok, usuarios} <- Cuentas.registrar_actividad(estado.usuarios, usuario, accion),
       :ok <- persistir(usuarios) do
    {:reply, :ok, %{estado | usuarios: usuarios}}
  else
    {:error, motivo} -> {:reply, {:error, motivo}, estado}
  end
end

  @impl true
  def handle_call({:conectar, usuario, clave, rol, zona}, _from, estado) do
    if MapSet.member?(estado.sesiones, usuario) do
      {:reply, {:error, :ya_conectado}, estado}
    else
      case Cuentas.conectar(estado.usuarios, usuario, clave, rol, zona) do
        {:ok, usuarios, encontrado, :registrado} ->
          case persistir(usuarios) do
            :ok ->
              {:reply, {:ok, encontrado, :registrado}, abrir_sesion(estado, usuarios, usuario)}

            {:error, motivo} ->
              {:reply, {:error, {:persistencia, motivo}}, estado}
          end

        {:ok, usuarios, encontrado, :autenticado} ->
          {:reply, {:ok, encontrado, :autenticado}, abrir_sesion(estado, usuarios, usuario)}

        {:error, _} = error ->
          {:reply, error, estado}
      end
    end
  end

  def handle_call({:desconectar, usuario}, _from, estado) do
    if MapSet.member?(estado.sesiones, usuario) do
      {:reply, :ok, %{estado | sesiones: MapSet.delete(estado.sesiones, usuario)}}
    else
      {:reply, {:error, :no_conectado}, estado}
    end
  end

  def handle_call({:conectado?, usuario}, _from, estado),
    do: {:reply, MapSet.member?(estado.sesiones, usuario), estado}

  def handle_call({:autorizar, usuario, accion}, _from, estado) do
    if MapSet.member?(estado.sesiones, usuario) do
      encontrado = Map.fetch!(estado.usuarios, usuario)

      if Cuentas.puede?(encontrado.rol, accion),
        do: {:reply, {:ok, encontrado}, estado},
        else: {:reply, {:error, :no_autorizado}, estado}
    else
      {:reply, {:error, :no_conectado}, estado}
    end
  end

  def handle_call({:obtener_usuario, usuario}, _from, estado),
    do: {:reply, Map.fetch(estado.usuarios, usuario), estado}

  defp abrir_sesion(estado, usuarios, usuario),
  do: %{estado | usuarios: usuarios, sesiones: MapSet.put(estado.sesiones, usuario)}

  defp persistir(usuarios) do
    registros = usuarios |> Map.values() |> Enum.map(&Cuentas.a_registro/1)
    Persistencia.guardar(:usuarios, registros)
  end

  defp cargar_usuarios(registros) do
    Enum.reduce_while(registros, {:ok, %{}}, fn registro, {:ok, acumulado} ->
      case Cuentas.de_registro(registro) do
        {:ok, usuario} -> {:cont, {:ok, Map.put(acumulado, usuario.usuario, usuario)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
