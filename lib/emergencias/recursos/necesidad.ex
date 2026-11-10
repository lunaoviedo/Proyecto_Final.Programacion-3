defmodule Emergencias.Recursos.Necesidad do
  @moduledoc """
  Define la estructura de una necesidad reportada en una zona.

  Permite realizar seguimiento desde que se solicita hasta que es atendida.
  """

  @enforce_keys [:id, :tipo, :cantidad, :zona, :prioridad, :responsable]

  # Nota que 'estado' y 'descripcion' no están en @enforce_keys.
  # A 'estado' le damos un valor por defecto, y 'descripcion' puede ser nulo.
  defstruct [
    :id,
    :tipo,
    :descripcion,
    :cantidad,
    :zona,
    :prioridad,
    :responsable,
    estado: :pendiente
  ]

  @type estado :: :pendiente | :asignada | :en_atencion | :atendida | :cancelada
  @type prioridad :: :critica | :alta | :media | :baja

  @type t :: %__MODULE__{
          id: String.t(),
          tipo: String.t(),
          descripcion: String.t() | nil,
          cantidad: pos_integer(),
          zona: String.t(),
          prioridad: prioridad(),
          responsable: String.t(),
          estado: estado()
        }
end
