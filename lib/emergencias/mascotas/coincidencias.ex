defmodule Emergencias.Mascotas.Coincidencias do
  @moduledoc """
  Búsqueda de posibles coincidencias entre mascotas perdidas y encontradas.

  Cada pareja formada por un reporte de tipo `:perdida` y uno de tipo `:encontrada`
  recibe un puntaje de similitud. La pareja se descarta si los reportes son del mismo
  tipo o de especies distintas; en caso contrario se suman los puntos de cada atributo:

    * color: 40 puntos si coincide.
    * zona: 30 puntos si coincide.
    * nombre: 25 puntos si ambos lo conocen y coincide.
    * características: hasta 20 puntos, proporcionales al índice de Jaccard entre los
      conjuntos de rasgos de ambos reportes.
    * tamaño: 15 puntos si coincide y 7 si es adyacente (pequeño y mediano, o mediano
      y grande).

  El puntaje máximo es 130. Una pareja se considera posible coincidencia cuando
  alcanza al menos 60 puntos.

  ## Criterio de diseño

  Se prefiere detectar de más a detectar de menos: una coincidencia no detectada
  mantiene separado a un animal de su familia, mientras que una candidata incorrecta
  solo requiere que una persona la descarte. Por eso el color y la zona, los atributos
  más fáciles de observar y más probables entre reportes cercanos, pesan más y bastan
  juntos (70 puntos) para superar el umbral. El nombre solo suma cuando ambos reportes
  lo conocen, y no penaliza cuando falta.

  Solo se consideran los reportes en estado `:activa`: los que ya están asociados o
  resueltos no participan en nuevas búsquedas.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  alias Emergencias.Mascotas.Mascota

  @peso_color 40
  @peso_zona 30
  @peso_nombre 25
  @peso_caracteristicas 20
  @peso_tamano 15
  @peso_tamano_adyacente 7
  @umbral 60

  @typedoc "Puntos obtenidos por cada atributo comparado."
  @type desglose :: %{
          color: non_neg_integer(),
          tamano: non_neg_integer(),
          zona: non_neg_integer(),
          nombre: non_neg_integer(),
          caracteristicas: non_neg_integer()
        }

  @typedoc "Pareja de reportes que supera el umbral de similitud."
  @type coincidencia :: %{
          perdida: String.t(),
          encontrada: String.t(),
          puntaje: non_neg_integer(),
          desglose: desglose()
        }

  @doc """
  Puntaje mínimo para considerar una pareja como posible coincidencia.

  ## Ejemplos

      iex> Emergencias.Mascotas.Coincidencias.umbral()
      60

  """
  @spec umbral() :: pos_integer()
  def umbral, do: @umbral

  @doc """
  Puntaje máximo que puede alcanzar una pareja.

  ## Ejemplos

      iex> Emergencias.Mascotas.Coincidencias.puntaje_maximo()
      130

  """
  @spec puntaje_maximo() :: pos_integer()
  def puntaje_maximo do
    @peso_color + @peso_zona + @peso_nombre + @peso_caracteristicas + @peso_tamano
  end

  @doc """
  Calcula los puntos que aporta cada atributo al comparar dos reportes.

  Retorna `{:error, :tipos_iguales}` si ambos reportes son del mismo tipo y
  `{:error, :especies_distintas}` si se trata de especies diferentes.
  """
  @spec desglose(Mascota.t(), Mascota.t()) ::
          {:ok, desglose()} | {:error, :tipos_iguales | :especies_distintas}
  def desglose(%Mascota{} = a, %Mascota{} = b) do
    cond do
      a.tipo == b.tipo ->
        {:error, :tipos_iguales}

      normalizar(a.especie) != normalizar(b.especie) ->
        {:error, :especies_distintas}

      true ->
        {:ok,
         %{
           color: puntos_texto(a.color, b.color, @peso_color),
           tamano: puntos_tamano(a.tamano, b.tamano),
           zona: puntos_texto(a.zona, b.zona, @peso_zona),
           nombre: puntos_nombre(a.nombre, b.nombre),
           caracteristicas: puntos_caracteristicas(a.caracteristicas, b.caracteristicas)
         }}
    end
  end

  @doc """
  Calcula el puntaje total de similitud entre dos reportes.
  """
  @spec puntaje(Mascota.t(), Mascota.t()) ::
          {:ok, non_neg_integer()} | {:error, :tipos_iguales | :especies_distintas}
  def puntaje(%Mascota{} = a, %Mascota{} = b) do
    with {:ok, detalle} <- desglose(a, b) do
      {:ok, detalle |> Map.values() |> Enum.sum()}
    end
  end

  @doc """
  Busca todas las posibles coincidencias entre los reportes `:activa`.

  Recibe el mapa de reportes (identificador => reporte). Retorna las parejas que
  alcanzan el umbral, ordenadas por puntaje descendente y, en caso de empate, por
  identificador de la perdida y luego de la encontrada.
  """
  @spec buscar(%{optional(String.t()) => Mascota.t()}) :: [coincidencia()]
  def buscar(reportes) when is_map(reportes) do
    activas = reportes |> Map.values() |> Enum.filter(&(&1.estado == :activa))
    perdidas = Enum.filter(activas, &(&1.tipo == :perdida))
    encontradas = Enum.filter(activas, &(&1.tipo == :encontrada))

    perdidas
    |> emparejar(encontradas)
    |> Enum.sort_by(&{-&1.puntaje, &1.perdida, &1.encontrada})
  end

  # Recorre recursivamente cada perdida y la compara con todas las encontradas.
  defp emparejar([], _encontradas), do: []

  defp emparejar([perdida | resto], encontradas),
    do: candidatas(perdida, encontradas) ++ emparejar(resto, encontradas)

  defp candidatas(_perdida, []), do: []

  defp candidatas(perdida, [encontrada | resto]) do
    case evaluar(perdida, encontrada) do
      {:ok, coincidencia} -> [coincidencia | candidatas(perdida, resto)]
      :descartada -> candidatas(perdida, resto)
    end
  end

  defp evaluar(perdida, encontrada) do
    with {:ok, detalle} <- desglose(perdida, encontrada),
         puntaje = detalle |> Map.values() |> Enum.sum(),
         true <- puntaje >= @umbral do
      {:ok,
       %{perdida: perdida.id, encontrada: encontrada.id, puntaje: puntaje, desglose: detalle}}
    else
      _ -> :descartada
    end
  end

  # -- Puntaje por atributo ----------------------------------------------------

  defp puntos_texto(a, b, peso), do: if(normalizar(a) == normalizar(b), do: peso, else: 0)

  defp puntos_tamano(tamano, tamano), do: @peso_tamano
  defp puntos_tamano(:pequeno, :mediano), do: @peso_tamano_adyacente
  defp puntos_tamano(:mediano, :pequeno), do: @peso_tamano_adyacente
  defp puntos_tamano(:mediano, :grande), do: @peso_tamano_adyacente
  defp puntos_tamano(:grande, :mediano), do: @peso_tamano_adyacente
  defp puntos_tamano(_a, _b), do: 0

  defp puntos_nombre(nil, _b), do: 0
  defp puntos_nombre(_a, nil), do: 0
  defp puntos_nombre(a, b), do: puntos_texto(a, b, @peso_nombre)

  # Índice de Jaccard: rasgos compartidos / rasgos distintos en total.
  defp puntos_caracteristicas(a, b) do
    conjunto_a = a |> Enum.map(&normalizar/1) |> MapSet.new()
    conjunto_b = b |> Enum.map(&normalizar/1) |> MapSet.new()
    total = conjunto_a |> MapSet.union(conjunto_b) |> MapSet.size()

    if total == 0 do
      0
    else
      comunes = conjunto_a |> MapSet.intersection(conjunto_b) |> MapSet.size()
      round(@peso_caracteristicas * comunes / total)
    end
  end

  defp normalizar(texto), do: texto |> String.trim() |> String.downcase()
end
