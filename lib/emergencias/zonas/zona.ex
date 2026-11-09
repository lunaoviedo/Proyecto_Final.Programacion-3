defmodule Emergencias.Zonas.Punto do
  @moduledoc """
  Define la estructura de datos para un punto de interés o afectación menor.
  ##informacion del proyecto
  - autor: Simon Lopez E, Luna Sofia Oviedo Rios, David Alejandro Henao Jaramillo
  - fecha: noviembre del 2026
  - licencia: GNU GPL v3
  """

  @enforce_keys [:codigo, :nombre]
  defstruct [:codigo, :nombre, afectados: 0]
end

defmodule Emergencias.Zonas.Sector do
  @moduledoc """
  Define la estructura de datos para un sector que agrupa múltiples puntos de afectación.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """
  @enforce_keys [:codigo, :nombre]
  defstruct [:codigo, :nombre, afectados: 0, puntos: []]
end

defmodule Emergencias.Zonas.Zona do
  @moduledoc """
  Define la estructura de datos raíz para una zona geográfica que contiene sectores y puntos.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """
  @enforce_keys [:codigo, :nombre, :nivel]
  defstruct [:codigo, :nombre, :nivel, afectados: 0, sectores: []]

  @doc """
  Devuelve la lista de la criticidad por nivel validos para una zona.
  """
  @niveles [:critico, :alto, :medio, :bajo]
  def niveles, do: @niveles
end
