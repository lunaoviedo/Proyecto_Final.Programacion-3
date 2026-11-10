defmodule Emergencias.Mascotas.Mascota do
  @moduledoc """
  Define la estructura de un reporte de mascota perdida o encontrada.

  Un reporte pasa por tres estados: `:activa` al registrarse, `:posible_coincidencia`
  cuando se le asocia un reporte de tipo contrario, y `:resuelta` cuando la
  coincidencia se confirma o el reporte se cierra. El campo `coincidencia_con`
  guarda el identificador del reporte asociado y permite impedir que un mismo
  reporte se resuelva dos veces.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  @enforce_keys [:id, :tipo, :especie, :color, :tamano, :zona, :contacto]
  defstruct [
    :id,
    :tipo,
    :especie,
    :nombre,
    :color,
    :tamano,
    :zona,
    :contacto,
    caracteristicas: [],
    estado: :activa,
    coincidencia_con: nil
  ]

  @typedoc "Tipo de reporte: la mascota se perdió o fue encontrada."
  @type tipo :: :perdida | :encontrada

  @typedoc "Estado del reporte dentro de su ciclo de vida."
  @type estado :: :activa | :posible_coincidencia | :resuelta

  @typedoc "Tamaño del animal."
  @type tamano :: :pequeno | :mediano | :grande

  @typedoc """
  Reporte de mascota.

    * `id`: identificador único del reporte.
    * `nombre`: nombre del animal, `nil` si se desconoce.
    * `caracteristicas`: rasgos distintivos, cada uno como una palabra o frase breve.
    * `zona`: código de la zona donde se perdió o se encontró.
    * `coincidencia_con`: identificador del reporte asociado, `nil` si no tiene.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          tipo: tipo(),
          especie: String.t(),
          nombre: String.t() | nil,
          color: String.t(),
          tamano: tamano(),
          zona: String.t(),
          contacto: String.t(),
          caracteristicas: [String.t()],
          estado: estado(),
          coincidencia_con: String.t() | nil
        }

  @tipos [:perdida, :encontrada]
  @estados [:activa, :posible_coincidencia, :resuelta]
  @tamanos [:pequeno, :mediano, :grande]

  @doc """
  Retorna los tipos de reporte válidos.
  """
  @spec tipos() :: [tipo()]
  def tipos, do: @tipos

  @doc """
  Retorna los estados válidos de un reporte.
  """
  @spec estados() :: [estado()]
  def estados, do: @estados

  @doc """
  Retorna los tamaños válidos.
  """
  @spec tamanos() :: [tamano()]
  def tamanos, do: @tamanos
end
