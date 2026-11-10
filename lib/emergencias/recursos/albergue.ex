defmodule Emergencias.Recursos.Albergue do
  @moduledoc """
  Define la estructura inmutable de un albergue en el sistema de emergencias.

  Mantiene el registro de la capacidad máxima y la ocupación actual para
  facilitar el control de cupos y evitar el sobrecupo.
  """

  # Obligamos a que estos datos se proporcionen siempre al crear el albergue
  @enforce_keys [:codigo, :nombre, :zona, :capacidad_maxima]

  # Definimos las claves. La ocupación inicial siempre será 0 por defecto.
  defstruct [
    :codigo,
    :nombre,
    :zona,
    :capacidad_maxima,
    ocupacion_actual: 0
  ]

  @typedoc """
  Tipo de datos para un Albergue.
  Garantiza mediante tipos que la capacidad y ocupación sean enteros no negativos.
  """
  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          zona: String.t(),
          capacidad_maxima: non_neg_integer(),
          ocupacion_actual: non_neg_integer()
        }
end
