defmodule Emergencias.Zonas.Catalogo do
  @moduledoc """
  Gestiona el catálogo de zonas geográficas, el registro de sectores y puntos,
  la validación de datos y la generación de resúmenes estructurados.
  ##informacion del proyecto
  - autor: Simon Lopez E, Luna Sofia Oviedo Rios, David Alejandro Henao Jaramillo
  - fecha: noviembre del 2026
  - licencia: GNU GPL v3
  """

  alias Emergencias.Zonas.{Zona, Sector, Punto, ArbolZonas}

  @niveles %{
    "critico" => :critico, "crítico" => :critico,
    "alto" => :alto,
    "medio" => :medio,
    "bajo" => :bajo
  }

  @doc """
  Registra una nueva zona en el catálogo tras validar sus parámetros y disponibilidad de código.
  """
  def registrar_zona(zonas, codigo, nombre, nivel, afectados \\ 0) do
    with :ok <- validar_texto(codigo, :codigo_invalido),
         :ok <- validar_texto(nombre, :nombre_invalido),
         {:ok, nivel} <- interpretar_nivel(nivel),
         :ok <- validar_afectados(afectados),
         :ok <- verificar_codigo_libre(zonas, codigo) do
      zona = %Zona{codigo: codigo, nombre: nombre, nivel: nivel, afectados: afectados}
      {:ok, Map.put(zonas, codigo, zona), zona}
    end
  end

  @doc """
  Registra un nuevo sector dentro de una zona existente.
  """
  def registrar_sector(zonas, codigo_zona, codigo, nombre, afectados \\ 0) do
    with :ok <- validar_texto(codigo, :codigo_invalido),
         :ok <- validar_texto(nombre, :nombre_invalido),
         :ok <- validar_afectados(afectados),
         {:ok, zona} <- obtener_zona(zonas, codigo_zona),
         :ok <- verificar_codigo_libre(zonas, codigo) do
      sector = %Sector{codigo: codigo, nombre: nombre, afectados: afectados}
      zona = %{zona | sectores: zona.sectores ++ [sector]}
      {:ok, Map.put(zonas, codigo_zona, zona), sector}
    end
  end

  @doc """
  Registra un nuevo punto dentro de un sector específico del catálogo.
  """
  def registrar_punto(zonas, codigo_sector, codigo, nombre, afectados \\ 0) do
    with :ok <- validar_texto(codigo, :codigo_invalido),
         :ok <- validar_texto(nombre, :nombre_invalido),
         :ok <- validar_afectados(afectados),
         {:ok, zona} <- zona_del_sector(Map.values(zonas), codigo_sector),
         :ok <- verificar_codigo_libre(zonas, codigo) do
      punto = %Punto{codigo: codigo, nombre: nombre, afectados: afectados}
      sectores = agregar_a_sector(zona.sectores, codigo_sector, punto)
      {:ok, Map.put(zonas, zona.codigo, %{zona | sectores: sectores}), punto}
    end
  end

  @doc """
  Obtiene una zona del catálogo a partir de su código único.
  """
  def obtener_zona(zonas, codigo) do
    case Map.fetch(zonas, codigo) do
      {:ok, zona} -> {:ok, zona}
      :error -> {:error, :zona_no_encontrada}
    end
  end

  @doc """
  Genera un mapa resumen con estadísticas detalladas de una zona, incluyendo totales y rutas.
  """
  def resumen(%Zona{} = zona) do
     %{
      codigo: zona.codigo,
      nombre: zona.nombre,
      nivel: zona.nivel,
      total_afectados: ArbolZonas.total_afectados(zona),
      total_sectores: length(zona.sectores),
      total_puntos: ArbolZonas.contar_puntos(zona),
      por_sector: totales_por_sector(zona.sectores),
      rutas: ArbolZonas.rutas(zona)
    }
  end

  #Funciones auxilliares requeridas en las funciones anteriores.
  defp totales_por_sector([]), do: []

  defp totales_por_sector([sector | resto]) do
    [
      %{codigo: sector.codigo, nombre: sector.nombre, total: ArbolZonas.total_sector(sector)}
      | totales_por_sector(resto)
    ]
  end

  defp zona_del_sector([], _codigo_sector), do: {:error, :sector_no_encontrado}

  defp zona_del_sector([zona | resto], codigo_sector) do
    if tiene_sector?(zona.sectores, codigo_sector),
      do: {:ok, zona},
      else: zona_del_sector(resto, codigo_sector)
  end

  defp tiene_sector?([], _codigo), do: false
  defp tiene_sector?([%Sector{codigo: codigo} | _], codigo), do: true
  defp tiene_sector?([_ | resto], codigo), do: tiene_sector?(resto, codigo)

  defp agregar_a_sector([], _codigo, _punto), do: []

  defp agregar_a_sector([%Sector{codigo: codigo} = sector | resto], codigo, punto),
    do: [%{sector | puntos: sector.puntos ++ [punto]} | resto]

  defp agregar_a_sector([sector | resto], codigo, punto),
    do: [sector | agregar_a_sector(resto, codigo, punto)]

  @doc """
  Convierte una estructura `Zona` y su jerarquía en un formato plano serializable.
  """
  def a_registro(%Zona{} = z) do
    %{
      "codigo" => z.codigo,
      "nombre" => z.nombre,
      "nivel" => Atom.to_string(z.nivel),
      "afectados" => z.afectados,
      "sectores" => sectores_a_registro(z.sectores)
    }
  end

  defp sectores_a_registro([]), do: []

  defp sectores_a_registro([s | resto]) do
    [
      %{
        "codigo" => s.codigo,
        "nombre" => s.nombre,
        "afectados" => s.afectados,
        "puntos" => puntos_a_registro(s.puntos)
      }
      | sectores_a_registro(resto)
    ]
  end

  defp puntos_a_registro([]), do: []

  defp puntos_a_registro([p | resto]),
    do: [%{"codigo" => p.codigo, "nombre" => p.nombre, "afectados" => p.afectados} | puntos_a_registro(resto)]

  @doc """
  Reconstruye una estructura `Zona` y su árbol a partir de un mapa de registro persistido.
  """
  def de_registro(
        %{"codigo" => c, "nombre" => n, "nivel" => nivel, "afectados" => a, "sectores" => sectores}
      ) do
    with {:ok, nivel} <- interpretar_nivel(nivel),
         {:ok, sectores} <- sectores_de_registro(sectores) do
      {:ok, %Zona{codigo: c, nombre: n, nivel: nivel, afectados: a, sectores: sectores}}
    end
  end

  def de_registro(_), do: {:error, :registro_invalido}

  defp sectores_de_registro([]), do: {:ok, []}

  defp sectores_de_registro([%{"codigo" => c, "nombre" => n, "afectados" => a, "puntos" => p} | resto]) do
    with {:ok, puntos} <- puntos_de_registro(p),
         {:ok, sectores} <- sectores_de_registro(resto) do
      {:ok, [%Sector{codigo: c, nombre: n, afectados: a, puntos: puntos} | sectores]}
    end
  end

  defp sectores_de_registro(_), do: {:error, :registro_invalido}

  defp puntos_de_registro([]), do: {:ok, []}

  defp puntos_de_registro([%{"codigo" => c, "nombre" => n, "afectados" => a} | resto]) do
    with {:ok, puntos} <- puntos_de_registro(resto) do
      {:ok, [%Punto{codigo: c, nombre: n, afectados: a} | puntos]}
    end
  end

  defp puntos_de_registro(_), do: {:error, :registro_invalido}

  # Validaciones Internas
  defp interpretar_nivel(nivel) when nivel in [:critico, :alto, :medio, :bajo], do: {:ok, nivel}

  defp interpretar_nivel(nivel) when is_binary(nivel) do
    case Map.fetch(@niveles, String.downcase(nivel)) do
      {:ok, n} -> {:ok, n}
      :error -> {:error, :nivel_invalido}
    end
  end

  defp interpretar_nivel(_), do: {:error, :nivel_invalido}

  defp validar_texto(t, _error) when is_binary(t) and byte_size(t) > 0, do: :ok
  defp validar_texto(_, error), do: {:error, error}

  defp validar_afectados(a) when is_integer(a) and a >= 0, do: :ok
  defp validar_afectados(_), do: {:error, :afectados_invalidos}

  defp verificar_codigo_libre(zonas, codigo) do
    en_uso? = Enum.any?(Map.values(zonas), fn z -> ArbolZonas.buscar_nodo(z, codigo) != :error end)
    if en_uso?, do: {:error, :codigo_existente}, else: :ok
  end

end
