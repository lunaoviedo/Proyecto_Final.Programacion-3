defmodule Emergencias.Informes do
  @moduledoc """
  Informes que cruzan la información de todos los servidores del sistema.

  Se usa en dos comandos:

    * `summary`: estado global (recursos restantes, necesidades pendientes,
      personas localizadas, mensajes y reportes de mascotas).
    * `zone_status`: además de la jerarquía de la zona, los albergues, necesidades,
      recursos, personas y mascotas asociados a ella.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  alias Emergencias.Familiares.ServidorFamiliares
  alias Emergencias.Mascotas.ServidorMascotas
  alias Emergencias.Recursos.{ServidorAlbergues, ServidorInventario, ServidorNecesidades}
  alias Emergencias.Zonas.{ArbolZonas, ServidorZonas}

  @type fuente :: [struct()] | :no_disponible

  @type datos :: %{
          zonas: fuente(),
          albergues: fuente(),
          recursos: fuente(),
          necesidades: fuente(),
          personas: fuente(),
          mensajes: fuente(),
          mascotas: fuente()
        }

  def global, do: leer_datos() |> resumen_global() |> formatear_global()

  def detalle_zona(codigo), do: codigo |> asociados_a_zona(leer_datos()) |> formatear_zona()
  @spec leer_datos() :: datos()
  def leer_datos do
    %{
      zonas: leer(fn -> ServidorZonas.listar_zonas() end),
      albergues: leer(fn -> ServidorAlbergues.obtener_albergues() end),
      recursos: leer(fn -> ServidorInventario.obtener_inventario() end),
      necesidades: leer(fn -> ServidorNecesidades.listar_necesidades() end),
      personas: leer(fn -> ServidorFamiliares.consultar_personas([]) end),
      mensajes: leer(fn -> ServidorFamiliares.consultar_mensajes([]) end),
      mascotas: leer(fn -> ServidorMascotas.consultar([]) end)
    }
  end

  # Los servidores responden con una lista o con `{:ok, lista}`.
  defp leer(funcion) do
    case funcion.() do
      lista when is_list(lista) -> lista
      {:ok, lista} when is_list(lista) -> lista
      _otro -> :no_disponible
    end
  catch
    :exit, _motivo -> :no_disponible
  end

  @doc """
  Calcula las estadísticas globales a partir de los datos leídos.

  Cada sección es un mapa de estadísticas o `:no_disponible`.
  """
  @spec resumen_global(datos()) :: map()
  def resumen_global(datos) do
    %{
      zonas: calcular(datos.zonas, &estadisticas_zonas/1),
      albergues: calcular(datos.albergues, &estadisticas_albergues/1),
      recursos: calcular(datos.recursos, &Util2.ordenar(&1, :asc, fn r -> r.cantidad end)),
      necesidades: calcular(datos.necesidades, &estadisticas_necesidades/1),
      personas: calcular(datos.personas, &estadisticas_personas/1),
      mensajes: calcular(datos.mensajes, &estadisticas_mensajes/1),
      mascotas: calcular(datos.mascotas, &estadisticas_mascotas/1)
    }
  end

  defp calcular(:no_disponible, _funcion), do: :no_disponible
  defp calcular(lista, funcion) when is_list(lista), do: funcion.(lista)

  defp estadisticas_zonas(zonas) do
    %{
      total: length(zonas),
      afectados: zonas |> Enum.map(&ArbolZonas.total_afectados/1) |> Enum.sum()
    }
  end

  defp estadisticas_albergues(albergues) do
    %{
      total: length(albergues),
      capacidad: albergues |> Enum.map(& &1.capacidad_maxima) |> Enum.sum(),
      ocupadas: albergues |> Enum.map(&length(&1.ocupacion)) |> Enum.sum()
    }
  end

  defp estadisticas_necesidades(necesidades) do
    %{
      total: length(necesidades),
      pendientes: Enum.count(necesidades, &(&1.estado == :pendiente)),
      satisfechas: Enum.count(necesidades, &(&1.estado == :satisfecha))
    }
  end

  defp estadisticas_personas(personas) do
    %{
      total: length(personas),
      por_estado: Enum.frequencies_by(personas, & &1.estado),
      localizadas: Enum.filter(personas, &(&1.estado == :localizada))
    }
  end

  defp estadisticas_mensajes(mensajes) do
    %{
      total: length(mensajes),
      pendientes: Enum.count(mensajes, &(&1.estado == :pendiente)),
      entregados: Enum.count(mensajes, &(&1.estado == :entregado))
    }
  end

  defp estadisticas_mascotas(mascotas) do
    %{
      total: length(mascotas),
      perdidas: Enum.count(mascotas, &(&1.tipo == :perdida)),
      encontradas: Enum.count(mascotas, &(&1.tipo == :encontrada)),
      posibles: Enum.count(mascotas, &(&1.estado == :posible_coincidencia)),
      resueltas: Enum.count(mascotas, &(&1.estado == :resuelta))
    }
  end

  @spec formatear_global(map()) :: String.t()
  def formatear_global(r) do
    ["=== RESUMEN GLOBAL ==="]
    |> Kernel.++(linea_zonas(r.zonas))
    |> Kernel.++(linea_albergues(r.albergues))
    |> Kernel.++(lineas_recursos(r.recursos))
    |> Kernel.++(linea_necesidades(r.necesidades))
    |> Kernel.++(lineas_personas(r.personas))
    |> Kernel.++(linea_mensajes(r.mensajes))
    |> Kernel.++(linea_mascotas(r.mascotas))
    |> Enum.join("\n")
  end

  defp linea_zonas(:no_disponible), do: ["Zonas: no disponible"]

  defp linea_zonas(%{total: total, afectados: afectados}),
    do: ["Zonas: #{total} (#{afectados} personas afectadas en total)"]

  defp linea_albergues(:no_disponible), do: ["Albergues: no disponible"]

  defp linea_albergues(%{total: total, capacidad: capacidad, ocupadas: ocupadas}),
    do: ["Albergues: #{total} (ocupación #{ocupadas}/#{capacidad})"]

  defp lineas_recursos(:no_disponible), do: ["Recursos restantes: no disponible"]
  defp lineas_recursos([]), do: ["Recursos restantes: ninguno registrado"]

  defp lineas_recursos(recursos) do
    ["Recursos restantes:" | Enum.map(recursos, &formato_recurso/1)]
  end

  defp linea_necesidades(:no_disponible), do: ["Necesidades: no disponible"]

  defp linea_necesidades(%{total: total, pendientes: pendientes, satisfechas: satisfechas}),
    do: ["Necesidades: #{pendientes} pendientes, #{satisfechas} satisfechas (#{total} en total)"]

  defp lineas_personas(:no_disponible), do: ["Personas: no disponible"]

  defp lineas_personas(%{total: total, por_estado: por_estado, localizadas: localizadas}) do
    detalle =
      por_estado
      |> Enum.sort()
      |> Enum.map_join(", ", fn {estado, cantidad} -> "#{estado} #{cantidad}" end)

    encabezado =
      if detalle == "",
        do: "Personas: #{total} registradas",
        else: "Personas: #{total} registradas (#{detalle})"

    case localizadas do
      [] ->
        [encabezado, "Personas localizadas: ninguna"]
      _ ->
        [encabezado, "Personas localizadas: #{length(localizadas)}"] ++
          Enum.map(localizadas, &"  - #{&1.nombre} (doc. #{&1.documento}, zona #{&1.zona})")
    end
  end

  defp linea_mensajes(:no_disponible), do: ["Mensajes: no disponible"]
  defp linea_mensajes(%{total: total, pendientes: pendientes, entregados: entregados}),
    do: ["Mensajes: #{total} (#{pendientes} pendientes, #{entregados} entregados)"]
  defp linea_mascotas(:no_disponible), do: ["Mascotas: no disponible"]
  defp linea_mascotas(m) do
    [
      "Mascotas: #{m.total} reportes (#{m.perdidas} perdidas, #{m.encontradas} encontradas); " <>
        "#{m.posibles} con posible coincidencia, #{m.resueltas} resueltas"
    ]
  end
  @doc """
  Filtra, de los datos leídos, lo que pertenece a la zona `codigo`.

  Si no se pudo leer la lista de albergues, las necesidades de la zona quedan
  como `:no_disponible` (se asocian a través de los albergues).
  """
  @spec asociados_a_zona(String.t(), datos()) :: map()
  def asociados_a_zona(codigo, datos) do
    albergues = filtrar(datos.albergues, &(&1.zona == codigo))

    codigos_albergue =
      case albergues do
        :no_disponible -> :no_disponible
        lista -> Enum.map(lista, & &1.codigo)
      end

    %{
      albergues: albergues,
      necesidades: filtrar_por_albergue(datos.necesidades, codigos_albergue),
      recursos:
        filtrar(datos.recursos, fn r ->
          r.ubicacion == codigo or r.ubicacion in lista_o_vacia(codigos_albergue)
        end),
      personas: filtrar(datos.personas, &(&1.zona == codigo)),
      mascotas: filtrar(datos.mascotas, &(&1.zona == codigo))
    }
  end

  defp filtrar(:no_disponible, _funcion), do: :no_disponible
  defp filtrar(lista, funcion), do: Enum.filter(lista, funcion)

  defp filtrar_por_albergue(_necesidades, :no_disponible), do: :no_disponible

  defp filtrar_por_albergue(necesidades, codigos),
    do: filtrar(necesidades, &(&1.codigo_albergue in codigos))

  defp lista_o_vacia(:no_disponible), do: []
  defp lista_o_vacia(lista), do: lista

  def formatear_zona(a) do
    [
      bloque("Albergues", a.albergues, &formato_albergue/1),
      bloque("Necesidades", a.necesidades, &formato_necesidad/1),
      bloque("Recursos", a.recursos, &formato_recurso/1),
      bloque("Personas", a.personas, &formato_persona/1),
      bloque("Mascotas", a.mascotas, &formato_mascota/1)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp bloque(titulo, :no_disponible, _formato), do: ["  #{titulo}: no disponible"]
  defp bloque(titulo, [], _formato), do: ["  #{titulo}: sin registros"]

  defp bloque(titulo, lista, formato),
    do: ["  #{titulo} (#{length(lista)}):" | Enum.map(lista, &("  " <> formato.(&1)))]

  defp formato_recurso(r),
    do: "  - #{r.nombre} (#{r.codigo}): #{r.cantidad} #{r.unidad} en #{r.ubicacion}"

  defp formato_albergue(a),
    do: "  - #{a.codigo} #{a.nombre}: #{length(a.ocupacion)}/#{a.capacidad_maxima} ocupados"

  defp formato_necesidad(n),
    do:
      "  - [#{n.id}] #{n.cantidad} de #{n.recurso_requerido} para el albergue " <>
        "#{n.codigo_albergue} (#{n.estado})"

  defp formato_persona(p), do: "  - #{p.id} #{p.nombre} (#{p.estado})"

  defp formato_mascota(m),
    do: "  - #{m.id} [#{m.tipo}, #{m.estado}] #{m.especie} #{m.color}"
end
