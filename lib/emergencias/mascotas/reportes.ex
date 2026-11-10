defmodule Emergencias.Mascotas.Reportes do
  @moduledoc """
  Lógica de dominio de los reportes de mascotas perdidas y encontradas.

  Las funciones son puras: reciben el mapa de reportes (identificador => reporte)
  y retornan `{:ok, nuevos_reportes, valor}` o `{:error, motivo}`, sin lanzar
  excepciones ante situaciones esperadas. La persistencia y la concurrencia
  corresponden a `Emergencias.Mascotas.ServidorMascotas`.

  ## Ciclo de vida de un reporte

      activa <-> posible_coincidencia
      activa -> resuelta
      posible_coincidencia -> resuelta

  El estado `:resuelta` es final: un reporte no puede cerrarse dos veces.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  alias Emergencias.Mascotas.Mascota

  @typedoc "Colección de reportes indexada por identificador."
  @type reportes :: %{optional(String.t()) => Mascota.t()}

  @typedoc "Motivo de un error de dominio."
  @type motivo :: atom() | tuple()

  @typedoc "Pareja de reportes afectados por una operación."
  @type pareja :: {Mascota.t(), Mascota.t()}

  # -- Registro ----------------------------------------------------------------

  @doc """
  Registra un reporte nuevo en estado `:activa`.

  `atributos` es un mapa con las claves `:id`, `:tipo`, `:especie`, `:color`,
  `:tamano`, `:zona`, `:contacto` y, opcionalmente, `:nombre` y `:caracteristicas`.
  El tipo admite `"perdida"`, `"encontrada"`, `"lost"` y `"found"`. Un nombre vacío
  o `"desconocido"` se guarda como `nil`.
  """
  @spec registrar(reportes(), map()) :: {:ok, reportes(), Mascota.t()} | {:error, motivo()}
  def registrar(reportes, atributos) when is_map(reportes) and is_map(atributos) do
    with {:ok, id} <- texto(atributos[:id], :id_invalido),
         :ok <- verificar_id_libre(reportes, id),
         {:ok, tipo} <- interpretar_tipo(atributos[:tipo]),
         {:ok, especie} <- texto_normalizado(atributos[:especie], :especie_invalida),
         {:ok, nombre} <- interpretar_nombre(Map.get(atributos, :nombre)),
         {:ok, color} <- texto_normalizado(atributos[:color], :color_invalido),
         {:ok, tamano} <- interpretar_tamano(atributos[:tamano]),
         {:ok, zona} <- texto(atributos[:zona], :zona_invalida),
         {:ok, contacto} <- texto(atributos[:contacto], :contacto_invalido),
         {:ok, caracteristicas} <-
           interpretar_caracteristicas(Map.get(atributos, :caracteristicas, [])) do
      mascota = %Mascota{
        id: id,
        tipo: tipo,
        especie: especie,
        nombre: nombre,
        color: color,
        tamano: tamano,
        zona: zona,
        contacto: contacto,
        caracteristicas: caracteristicas
      }

      {:ok, Map.put(reportes, id, mascota), mascota}
    end
  end

  @doc """
  Genera el siguiente identificador libre, con el formato `MA001`, `MA002`, etc.

  ## Ejemplos

      iex> Emergencias.Mascotas.Reportes.siguiente_id(%{})
      "MA001"

  """
  @spec siguiente_id(reportes()) :: String.t()
  def siguiente_id(reportes), do: generar_id(reportes, map_size(reportes) + 1)

  defp generar_id(reportes, numero) do
    id = "MA" <> String.pad_leading(Integer.to_string(numero), 3, "0")

    if Map.has_key?(reportes, id), do: generar_id(reportes, numero + 1), else: id
  end

  # -- Consultas ---------------------------------------------------------------

  @doc """
  Retorna el reporte con el identificador dado.
  """
  @spec obtener(reportes(), String.t()) :: {:ok, Mascota.t()} | {:error, :reporte_no_encontrado}
  def obtener(reportes, id) do
    case Map.fetch(reportes, id) do
      {:ok, mascota} -> {:ok, mascota}
      :error -> {:error, :reporte_no_encontrado}
    end
  end

  @doc """
  Consulta los reportes que cumplen todos los filtros, ordenados por identificador.

  Los filtros son una lista de pares con las claves `:especie`, `:zona`, `:estado`
  y `:tipo`. Sin filtros retorna todos los reportes.
  """
  @spec consultar(reportes(), keyword()) :: {:ok, [Mascota.t()]} | {:error, motivo()}
  def consultar(reportes, filtros \\ []) when is_map(reportes) and is_list(filtros) do
    with {:ok, filtros} <- normalizar_filtros(filtros) do
      lista = reportes |> Map.values() |> Enum.sort_by(& &1.id)
      {:ok, filtrar(lista, filtros)}
    end
  end

  defp normalizar_filtros([]), do: {:ok, []}

  defp normalizar_filtros([{clave, valor} | resto])
       when clave in [:especie, :zona, :estado, :tipo] do
    with {:ok, normalizado} <- normalizar_filtro(clave, valor),
         {:ok, otros} <- normalizar_filtros(resto) do
      {:ok, [{clave, normalizado} | otros]}
    end
  end

  defp normalizar_filtros([{clave, _valor} | _resto]), do: {:error, {:filtro_invalido, clave}}
  defp normalizar_filtros([otro | _resto]), do: {:error, {:filtro_invalido, otro}}

  defp normalizar_filtro(:especie, valor) when is_binary(valor), do: {:ok, normalizar(valor)}
  defp normalizar_filtro(:zona, valor) when is_binary(valor), do: {:ok, String.trim(valor)}
  defp normalizar_filtro(:estado, valor), do: interpretar_estado(valor)
  defp normalizar_filtro(:tipo, valor), do: interpretar_tipo(valor)
  defp normalizar_filtro(clave, _valor), do: {:error, {:filtro_invalido, clave}}

  defp filtrar([], _filtros), do: []

  defp filtrar([mascota | resto], filtros) do
    if cumple?(mascota, filtros),
      do: [mascota | filtrar(resto, filtros)],
      else: filtrar(resto, filtros)
  end

  defp cumple?(_mascota, []), do: true

  defp cumple?(mascota, [{:especie, valor} | resto]),
    do: mascota.especie == valor and cumple?(mascota, resto)

  defp cumple?(mascota, [{:zona, valor} | resto]),
    do: mascota.zona == valor and cumple?(mascota, resto)

  defp cumple?(mascota, [{:estado, valor} | resto]),
    do: mascota.estado == valor and cumple?(mascota, resto)

  defp cumple?(mascota, [{:tipo, valor} | resto]),
    do: mascota.tipo == valor and cumple?(mascota, resto)

  # -- Transiciones de estado --------------------------------------------------

  @doc """
  Indica si un reporte puede pasar del estado `desde` al estado `hacia`.

  ## Ejemplos

      iex> Emergencias.Mascotas.Reportes.transicion_valida?(:activa, :posible_coincidencia)
      true

      iex> Emergencias.Mascotas.Reportes.transicion_valida?(:resuelta, :activa)
      false

  """
  @spec transicion_valida?(Mascota.estado(), Mascota.estado()) :: boolean()
  def transicion_valida?(:activa, :posible_coincidencia), do: true
  def transicion_valida?(:posible_coincidencia, :activa), do: true
  def transicion_valida?(:posible_coincidencia, :resuelta), do: true
  def transicion_valida?(:activa, :resuelta), do: true
  def transicion_valida?(_desde, _hacia), do: false

  @doc """
  Marca dos reportes de tipo contrario como posible coincidencia.

  Cada uno queda enlazado al otro mediante `coincidencia_con`.
  """
  @spec asociar(reportes(), String.t(), String.t()) ::
          {:ok, reportes(), pareja()} | {:error, motivo()}
  def asociar(reportes, id_a, id_b) do
    with {:ok, a, b} <- validar_pareja(reportes, id_a, id_b, :posible_coincidencia) do
      actualizar(reportes, a, b, :posible_coincidencia, b.id, a.id)
    end
  end

  @doc """
  Confirma la coincidencia entre dos reportes y cierra ambos.

  Puede confirmarse una pareja que estaba como posible coincidencia o dos reportes
  activos que no tenían ninguna asociación. Un reporte ya resuelto no puede cerrarse
  de nuevo.
  """
  @spec confirmar(reportes(), String.t(), String.t()) ::
          {:ok, reportes(), pareja()} | {:error, motivo()}
  def confirmar(reportes, id_a, id_b) do
    with {:ok, a, b} <- validar_pareja(reportes, id_a, id_b, :resuelta) do
      actualizar(reportes, a, b, :resuelta, b.id, a.id)
    end
  end

  @doc """
  Descarta una posible coincidencia y devuelve ambos reportes al estado `:activa`.
  """
  @spec descartar(reportes(), String.t()) :: {:ok, reportes(), pareja()} | {:error, motivo()}
  def descartar(reportes, id) do
    with {:ok, mascota} <- obtener(reportes, id),
         :ok <- verificar_pendiente(mascota),
         {:ok, pareja} <- obtener(reportes, mascota.coincidencia_con),
         :ok <- verificar_transicion(mascota, :activa),
         :ok <- verificar_transicion(pareja, :activa) do
      actualizar(reportes, mascota, pareja, :activa, nil, nil)
    end
  end

  defp validar_pareja(reportes, id_a, id_b, destino) do
    with {:ok, a, b} <- obtener_pareja(reportes, id_a, id_b),
         :ok <- verificar_abiertos(a, b),
         :ok <- verificar_tipos_opuestos(a, b),
         :ok <- verificar_vinculos(a, b),
         :ok <- verificar_transicion(a, destino),
         :ok <- verificar_transicion(b, destino) do
      {:ok, a, b}
    end
  end

  defp obtener_pareja(_reportes, id, id), do: {:error, :mismo_reporte}

  defp obtener_pareja(reportes, id_a, id_b) do
    with {:ok, a} <- obtener(reportes, id_a),
         {:ok, b} <- obtener(reportes, id_b) do
      {:ok, a, b}
    end
  end

  defp verificar_abiertos(%Mascota{estado: :resuelta}, _b), do: {:error, :reporte_resuelto}
  defp verificar_abiertos(_a, %Mascota{estado: :resuelta}), do: {:error, :reporte_resuelto}
  defp verificar_abiertos(_a, _b), do: :ok

  defp verificar_tipos_opuestos(%Mascota{tipo: tipo}, %Mascota{tipo: tipo}),
    do: {:error, :tipos_iguales}

  defp verificar_tipos_opuestos(_a, _b), do: :ok

  defp verificar_vinculos(a, b) do
    if vinculo_libre?(a.coincidencia_con, b.id) and vinculo_libre?(b.coincidencia_con, a.id),
      do: :ok,
      else: {:error, :ya_asociado_a_otro}
  end

  defp vinculo_libre?(nil, _id), do: true
  defp vinculo_libre?(id, id), do: true
  defp vinculo_libre?(_otro, _id), do: false

  defp verificar_transicion(%Mascota{estado: actual}, destino) do
    if transicion_valida?(actual, destino),
      do: :ok,
      else: {:error, {:transicion_invalida, actual, destino}}
  end

  defp verificar_pendiente(%Mascota{estado: :posible_coincidencia, coincidencia_con: id})
       when is_binary(id), do: :ok

  defp verificar_pendiente(%Mascota{estado: :resuelta}), do: {:error, :reporte_resuelto}
  defp verificar_pendiente(_mascota), do: {:error, :sin_coincidencia_pendiente}

  defp actualizar(reportes, a, b, estado, vinculo_a, vinculo_b) do
    nueva_a = %{a | estado: estado, coincidencia_con: vinculo_a}
    nueva_b = %{b | estado: estado, coincidencia_con: vinculo_b}
    nuevos = reportes |> Map.put(a.id, nueva_a) |> Map.put(b.id, nueva_b)

    {:ok, nuevos, {nueva_a, nueva_b}}
  end

  # -- Persistencia ------------------------------------------------------------

  @doc """
  Convierte un reporte en un mapa plano apto para persistencia.
  """
  @spec a_registro(Mascota.t()) :: map()
  def a_registro(%Mascota{} = m) do
    %{
      "id" => m.id,
      "tipo" => Atom.to_string(m.tipo),
      "especie" => m.especie,
      "nombre" => m.nombre,
      "color" => m.color,
      "tamano" => Atom.to_string(m.tamano),
      "zona" => m.zona,
      "contacto" => m.contacto,
      "caracteristicas" => m.caracteristicas,
      "estado" => Atom.to_string(m.estado),
      "coincidencia_con" => m.coincidencia_con
    }
  end

  @doc """
  Reconstruye un reporte a partir de un registro persistido.
  """
  @spec de_registro(map()) :: {:ok, Mascota.t()} | {:error, motivo()}
  def de_registro(
        %{
          "id" => id,
          "tipo" => tipo,
          "especie" => especie,
          "color" => color,
          "tamano" => tamano,
          "zona" => zona,
          "contacto" => contacto
        } = registro
      )
      when is_binary(id) and is_binary(especie) and is_binary(color) and is_binary(zona) and
             is_binary(contacto) do
    with {:ok, tipo} <- interpretar_tipo(tipo),
         {:ok, tamano} <- interpretar_tamano(tamano),
         {:ok, nombre} <- interpretar_nombre(Map.get(registro, "nombre")),
         {:ok, caracteristicas} <-
           interpretar_caracteristicas(Map.get(registro, "caracteristicas", [])),
         {:ok, estado} <- interpretar_estado(Map.get(registro, "estado", "activa")),
         {:ok, vinculo} <- interpretar_vinculo(Map.get(registro, "coincidencia_con")) do
      {:ok,
       %Mascota{
         id: id,
         tipo: tipo,
         especie: especie,
         nombre: nombre,
         color: color,
         tamano: tamano,
         zona: zona,
         contacto: contacto,
         caracteristicas: caracteristicas,
         estado: estado,
         coincidencia_con: vinculo
       }}
    end
  end

  def de_registro(_registro), do: {:error, :registro_invalido}

  # -- Validación y conversión -------------------------------------------------

  defp verificar_id_libre(reportes, id) do
    if Map.has_key?(reportes, id), do: {:error, :id_existente}, else: :ok
  end

  defp normalizar(texto), do: texto |> String.trim() |> String.downcase()

  defp texto(valor, error) when is_binary(valor) do
    case String.trim(valor) do
      "" -> {:error, error}
      limpio -> {:ok, limpio}
    end
  end

  defp texto(_valor, error), do: {:error, error}

  defp texto_normalizado(valor, error) do
    with {:ok, limpio} <- texto(valor, error), do: {:ok, String.downcase(limpio)}
  end

  defp interpretar_tipo(tipo) when tipo in [:perdida, :encontrada], do: {:ok, tipo}

  defp interpretar_tipo(tipo) when is_binary(tipo) do
    case normalizar(tipo) do
      valor when valor in ["perdida", "lost"] -> {:ok, :perdida}
      valor when valor in ["encontrada", "found"] -> {:ok, :encontrada}
      _ -> {:error, :tipo_invalido}
    end
  end

  defp interpretar_tipo(_tipo), do: {:error, :tipo_invalido}

  defp interpretar_tamano(tamano) when tamano in [:pequeno, :mediano, :grande], do: {:ok, tamano}

  defp interpretar_tamano(tamano) when is_binary(tamano) do
    case normalizar(tamano) do
      valor when valor in ["pequeno", "pequeño"] -> {:ok, :pequeno}
      "mediano" -> {:ok, :mediano}
      "grande" -> {:ok, :grande}
      _ -> {:error, :tamano_invalido}
    end
  end

  defp interpretar_tamano(_tamano), do: {:error, :tamano_invalido}

  defp interpretar_estado(estado) when estado in [:activa, :posible_coincidencia, :resuelta],
    do: {:ok, estado}

  defp interpretar_estado(estado) when is_binary(estado) do
    case normalizar(estado) do
      "activa" -> {:ok, :activa}
      "posible_coincidencia" -> {:ok, :posible_coincidencia}
      "resuelta" -> {:ok, :resuelta}
      _ -> {:error, :estado_invalido}
    end
  end

  defp interpretar_estado(_estado), do: {:error, :estado_invalido}

  defp interpretar_nombre(nil), do: {:ok, nil}

  defp interpretar_nombre(nombre) when is_binary(nombre) do
    case String.trim(nombre) do
      "" -> {:ok, nil}
      limpio -> if String.downcase(limpio) == "desconocido", do: {:ok, nil}, else: {:ok, limpio}
    end
  end

  defp interpretar_nombre(_nombre), do: {:error, :nombre_invalido}

  defp interpretar_vinculo(nil), do: {:ok, nil}
  defp interpretar_vinculo(id) when is_binary(id), do: {:ok, id}
  defp interpretar_vinculo(_valor), do: {:error, :registro_invalido}

  defp interpretar_caracteristicas(lista) when is_list(lista),
    do: normalizar_caracteristicas(lista, [])

  defp interpretar_caracteristicas(_otro), do: {:error, :caracteristicas_invalidas}

  defp normalizar_caracteristicas([], acumuladas), do: {:ok, Enum.reverse(acumuladas)}

  defp normalizar_caracteristicas([caracteristica | resto], acumuladas)
       when is_binary(caracteristica) do
    case normalizar(caracteristica) do
      "" ->
        normalizar_caracteristicas(resto, acumuladas)

      limpia ->
        if limpia in acumuladas,
          do: normalizar_caracteristicas(resto, acumuladas),
          else: normalizar_caracteristicas(resto, [limpia | acumuladas])
    end
  end

  defp normalizar_caracteristicas([_otro | _resto], _acumuladas),
    do: {:error, :caracteristicas_invalidas}
end
