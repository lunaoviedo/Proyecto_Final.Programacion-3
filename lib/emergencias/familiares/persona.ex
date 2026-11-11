defmodule Emergencias.Familiares.Persona do
  @moduledoc """
  Define la estructura de una persona afectada por la emergencia.

  Cada persona conserva un historial con todos los estados por los que ha pasado y
  la fecha de cada cambio, desde su registro hasta su reunificación con la familia.
  Las reglas de registro y de cambio de estado están en
  `Emergencias.Familiares.Personas`.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  @enforce_keys [:id, :nombre, :documento, :edad, :zona]
  defstruct [
    :id,
    :nombre,
    :documento,
    :edad,
    :zona,
    estado: :reportada,
    historial: []
  ]

  @typedoc "Situación de la persona dentro del proceso de localización y reunificación."
  @type estado ::
          :sin_informacion | :reportada | :localizada | :trasladada | :en_albergue | :reunificada

  @typedoc "Entrada del historial: el estado adoptado y el instante del cambio."
  @type cambio :: %{estado: estado(), fecha: DateTime.t()}

  @typedoc """
  Persona afectada.

    * `id`: identificador único del registro.
    * `documento`: documento de identidad, en mayúsculas y sin espacios.
    * `zona`: código de la zona donde se encuentra o se la vio por última vez.
    * `historial`: cambios de estado en orden cronológico; el último coincide con `estado`.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          nombre: String.t(),
          documento: String.t(),
          edad: non_neg_integer(),
          zona: String.t(),
          estado: estado(),
          historial: [cambio()]
        }

  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]

  @doc """
  Retorna los estados válidos de una persona, en el orden habitual del proceso.
  """
  @spec estados() :: [estado()]
  def estados, do: @estados
end
