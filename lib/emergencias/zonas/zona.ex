defmodule Emergencias.Zonas.Punto do

  @enforce_keys [:codigo, :nombre]
  defstruct [:codigo, :nombre, afectados: 0]
end

defmodule Emergencias.Zonas.Sector do
  @enforce_keys [:codigo, :nombre]
  defstruct [:codigo, :nombre, afectados: 0, puntos: []]
end

defmodule Emergencias.Zonas.Zona do
  @enforce_keys [:codigo, :nombre, :nivel]
  defstruct [:codigo, :nombre, :nivel, afectados: 0, sectores: []]

  @niveles [:critico, :alto, :medio, :bajo]
  def niveles, do: @niveles
end
