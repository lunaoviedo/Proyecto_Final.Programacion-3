defmodule Emergencias.Persistencia do
  @moduledoc """
  Persistencia en archivos de texto plano con formato JSON Lines.

  Cada entidad del sistema (usuarios, zonas, mascotas, personas, etc.) se almacena
  en su propio archivo dentro del directorio de datos, con un registro por línea:

      data/mascotas.jsonl
      data/personas.jsonl

  ## Convenciones

    * Un registro es un mapa cuyos valores son cadenas, números, booleanos, `nil`,
      listas u otros mapas. Los átomos se serializan como cadenas.
    * Al cargar, las claves y los valores textuales se devuelven como cadenas. La
      conversión a átomos o estructuras corresponde al módulo de dominio.
    * Cada archivo debe ser escrito por un único proceso, normalmente el servidor
      de la entidad correspondiente.
    * Ninguna función lanza excepciones ante situaciones esperadas: todas retornan
      `:ok`, `{:ok, valor}` o `{:error, motivo}`.

  ## Configuración

  El directorio de datos se define con:

      config :emergencias, data_dir: "ruta/de/datos"

  Si no se configura, se utiliza `"data"`.
  """

  @typedoc "Nombre de la entidad persistida. Determina el nombre del archivo."
  @type entidad :: atom()

  @typedoc "Registro a persistir: un mapa serializable como JSON."
  @type registro :: %{optional(String.t() | atom()) => term()}

  @typedoc "Registro leído del archivo: claves siempre como cadenas."
  @type registro_cargado :: %{optional(String.t()) => term()}

  @typedoc "Motivo de un error de persistencia."
  @type motivo :: term()

  @doc """
  Retorna el directorio donde se almacenan los archivos de datos.
  """
  @spec directorio() :: Path.t()
  def directorio, do: Application.get_env(:emergencias, :data_dir, "data")

  @doc """
  Retorna la ruta del archivo asociado a una entidad.

  ## Ejemplos

      iex> Emergencias.Persistencia.ruta_archivo(:mascotas) |> Path.basename()
      "mascotas.jsonl"

  """
  @spec ruta_archivo(entidad()) :: Path.t()
  def ruta_archivo(entidad) when is_atom(entidad) do
    Path.join(directorio(), "#{entidad}.jsonl")
  end

  @doc """
  Reemplaza el contenido del archivo de la entidad por la lista de registros dada.

  Los registros se escriben primero en un archivo temporal que luego se renombra,
  por lo que un fallo durante la escritura no altera el archivo previo.

  Retorna `{:error, {:registro_invalido, valor}}` si algún elemento no es un mapa y
  `{:error, {:no_codificable, detalle}}` si un registro contiene valores que no se
  pueden representar como JSON (tuplas, PIDs, estructuras sin convertir).

  ## Ejemplos

      :ok = Emergencias.Persistencia.guardar(:mascotas, [%{"id" => "M001", "especie" => "perro"}])

  """
  @spec guardar(entidad(), [registro()]) :: :ok | {:error, motivo()}
  def guardar(entidad, registros) when is_atom(entidad) and is_list(registros) do
    ruta = ruta_archivo(entidad)
    temporal = ruta <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(ruta)),
         :ok <- escribir_archivo(temporal, registros),
         :ok <- File.rename(temporal, ruta) do
      :ok
    else
      {:error, _motivo} = error ->
        File.rm(temporal)
        error
    end
  end

  @doc """
  Agrega un registro al final del archivo de la entidad sin reescribirlo.

  Está pensada para historiales y movimientos. Si el archivo no existe, lo crea.

  ## Ejemplos

      :ok = Emergencias.Persistencia.agregar(:movimientos, %{"recurso" => "R001", "cantidad" => 30})

  """
  @spec agregar(entidad(), registro()) :: :ok | {:error, motivo()}
  def agregar(entidad, registro) when is_atom(entidad) and is_map(registro) do
    ruta = ruta_archivo(entidad)

    with {:ok, linea} <- codificar(registro),
         :ok <- File.mkdir_p(Path.dirname(ruta)) do
      File.write(ruta, linea <> "\n", [:append])
    end
  end

  @doc """
  Lee todos los registros de la entidad en el orden en que fueron almacenados.

  Las líneas en blanco se ignoran. Si el archivo no existe retorna `{:ok, []}`,
  pues es la situación esperada antes de la primera escritura.

  ## Retorno

    * `{:ok, registros}`: lista de mapas con claves de tipo cadena.
    * `{:error, {:linea_invalida, numero}}`: la línea física `numero` (desde 1) no
      contiene un objeto JSON válido.
    * `{:error, motivo}`: error del sistema de archivos, por ejemplo `:eacces`.

  ## Ejemplos

      {:ok, [%{"id" => "M001"} | _]} = Emergencias.Persistencia.cargar(:mascotas)

  """
  @spec cargar(entidad()) :: {:ok, [registro_cargado()]} | {:error, motivo()}
  def cargar(entidad) when is_atom(entidad) do
    ruta = ruta_archivo(entidad)

    if File.exists?(ruta) do
      leer_archivo(ruta)
    else
      {:ok, []}
    end
  end

  # -- Escritura ---------------------------------------------------------------

  defp escribir_archivo(ruta, registros) do
    case File.open(ruta, [:write, :utf8]) do
      {:ok, dispositivo} ->
        try do
          escribir_lineas(dispositivo, registros)
        rescue
          e -> {:error, {:no_codificable, Exception.message(e)}}
        after
          File.close(dispositivo)
        end

      {:error, _motivo} = error ->
        error
    end
  end

  # Escribe un registro por línea de forma recursiva, sin construir en memoria el
  # contenido completo del archivo.
  defp escribir_lineas(_dispositivo, []), do: :ok

  defp escribir_lineas(dispositivo, [registro | resto]) when is_map(registro) do
    IO.write(dispositivo, JSON.encode!(registro) <> "\n")
    escribir_lineas(dispositivo, resto)
  end

  defp escribir_lineas(_dispositivo, [otro | _resto]), do: {:error, {:registro_invalido, otro}}

  defp codificar(registro) do
    {:ok, JSON.encode!(registro)}
  rescue
    e -> {:error, {:no_codificable, Exception.message(e)}}
  end

  # -- Lectura -----------------------------------------------------------------

  defp leer_archivo(ruta) do
    resultado =
      ruta
      |> File.stream!()
      |> Stream.with_index(1)
      |> Stream.reject(fn {linea, _numero} -> String.trim(linea) == "" end)
      |> Enum.reduce_while({:ok, []}, fn {linea, numero}, {:ok, acumulado} ->
        case JSON.decode(String.trim(linea)) do
          {:ok, registro} when is_map(registro) -> {:cont, {:ok, [registro | acumulado]}}
          _ -> {:halt, {:error, {:linea_invalida, numero}}}
        end
      end)

    case resultado do
      {:ok, acumulado} -> {:ok, Enum.reverse(acumulado)}
      {:error, _motivo} = error -> error
    end
  rescue
    e in File.Error -> {:error, e.reason}
  end
end
