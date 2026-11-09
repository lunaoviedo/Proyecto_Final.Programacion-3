defmodule Emergencias.Zonas.ArbolZonas do

  alias Emergencias.Zonas.{Zona, Sector, Punto}

  def total_afectados(%Zona{afectados: a, sectores: sectores}), do: a + sumar_sectores(sectores)

  defp sumar_sectores([]), do: 0

  defp sumar_sectores([%Sector{afectados: a, puntos: puntos} | resto]), do: a + sumar_puntos(puntos) + sumar_sectores(resto)

  defp sumar_puntos([]), do: 0
  defp sumar_puntos([%Punto{afectados: a} | resto]), do: a + sumar_puntos(resto)

  def contar_puntos(%Zona{sectores: sectores}), do: contar_en_sectores(sectores)

  defp contar_en_sectores([]), do: 0

  defp contar_en_sectores([%Sector{puntos: puntos} | resto]), do: contar_lista(puntos) + contar_en_sectores(resto)

  defp contar_lista([]), do: 0
  defp contar_lista([_ | resto]), do: 1+ contar_lista(resto)

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

  def rutas(%Zona{nombre: nombre, sectores: sectores}), do: [nombre | rutas_sectores(sectores, nombre)]

  defp rutas_sectores([], _prefijo), do: []

  defp rutas_sectores([%Sector{nombre: nombre, puntos: puntos} | resto], prefijo) do
    ruta = prefijo <> " > " <> nombre
    [ruta | rutas_puntos(puntos, ruta)] ++ rutas_sectores(resto, prefijo)
  end

  defp rutas_puntos([], _prefijo), do: []

  defp rutas_puntos([%Punto{nombre: nombre} | resto], prefijo),
    do: [prefijo <> " > " <> nombre | rutas_puntos(resto, prefijo)]

  def total_sector(%Sector{afectados: a, puntos: puntos}), do: a + sumar_puntos(puntos)
end
