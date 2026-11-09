defmodule Emergencias.Zonas.ArbolZonas do
  @moduledoc """
  Proporciona funciones para recorrer, consultar y procesar la jerarquía en árbol
  de zonas, sectores y puntos de afectación.

  ##informacion del proyecto
  - autor: Simon Lopez E, Luna Sofia Oviedo Rios, David Alejandro Henao Jaramillo
  - fecha: noviembre del 2026
  - licencia: GNU GPL v3
  """

  alias Emergencias.Zonas.{Zona, Sector, Punto}

  @doc """
  Calcula el número total de personas afectadas en una zona, sumando los afectados
  directos de la zona, sus sectores y sus puntos.
  """
  def total_afectados(%Zona{afectados: a, sectores: sectores}), do: a + sumar_sectores(sectores)

  defp sumar_sectores([]), do: 0

  defp sumar_sectores([%Sector{afectados: a, puntos: puntos} | resto]), do: a + sumar_puntos(puntos) + sumar_sectores(resto)

  defp sumar_puntos([]), do: 0
  defp sumar_puntos([%Punto{afectados: a} | resto]), do: a + sumar_puntos(resto)

  @doc """
  Cuenta la cantidad total de puntos registrados dentro de todos los sectores de una zona.
  """
  def contar_puntos(%Zona{sectores: sectores}), do: contar_en_sectores(sectores)

  defp contar_en_sectores([]), do: 0

  defp contar_en_sectores([%Sector{puntos: puntos} | resto]), do: contar_lista(puntos) + contar_en_sectores(resto)

  defp contar_lista([]), do: 0
  defp contar_lista([_ | resto]), do: 1+ contar_lista(resto)

  @doc """
  Busca y retorna un nodo (zona, sector o punto) dentro del árbol a partir de su código único.
  """
  def buscar_nodo(%Zona{codigo: codigo} = zona, codigo), do: {:ok, zona}
  def buscar_nodo(%Zona{sectores: sectores}, codigo), do: buscar_en_sectores(sectores, codigo)

  defp buscar_en_sectores([], _codigo), do: :error
  defp buscar_en_sectores([%Sector{codigo: codigo} = sector | _], codigo), do: {:ok, sector}

  defp buscar_en_sectores([%Sector{puntos: puntos} | resto], codigo) do
    case buscar_en_puntos(puntos, codigo) do
      {:ok, _} = encontrado -> encontrado
      :error -> buscar_en_sectores(resto, codigo)
    end
  end

  defp buscar_en_puntos([], _codigo), do: :error
  defp buscar_en_puntos([%Punto{codigo: codigo} = punto | _], codigo), do: {:ok, punto}
  defp buscar_en_puntos([_ | resto], codigo), do: buscar_en_puntos(resto, codigo)

  @doc """
  Genera una lista con las rutas jerárquicas en formato de texto (ej. "Zona > Sector > Punto")
  para toda la estructura de la zona.
  """
  def rutas(%Zona{nombre: nombre, sectores: sectores}), do: [nombre | rutas_sectores(sectores, nombre)]

  defp rutas_sectores([], _prefijo), do: []

  defp rutas_sectores([%Sector{nombre: nombre, puntos: puntos} | resto], prefijo) do
    ruta = prefijo <> " > " <> nombre
    [ruta | rutas_puntos(puntos, ruta)] ++ rutas_sectores(resto, prefijo)
  end

  defp rutas_puntos([], _prefijo), do: []

  defp rutas_puntos([%Punto{nombre: nombre} | resto], prefijo),
    do: [prefijo <> " > " <> nombre | rutas_puntos(resto, prefijo)]

  @doc """
  Calcula el total de afectados en un sector específico incluyendo sus puntos dependientes.
  """
  def total_sector(%Sector{afectados: a, puntos: puntos}), do: a + sumar_puntos(puntos)
end
