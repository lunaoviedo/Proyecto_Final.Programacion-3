defmodule Emergencias.Recursos.Necesidad do
  @moduledoc """
  Estructura inmutable que representa una solicitud de recursos.
  """

  @enforce_keys [:id, :tipo, :descripcion, :cantidad, :zona, :prioridad, :responsable]
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

  @type t :: %__MODULE__{
          id: String.t(),
          tipo: String.t(),
          descripcion: String.t(),
          cantidad: pos_integer(),
          zona: String.t(),
          prioridad: integer(), # Por ejemplo: 1 (Alta), 2 (Media), 3 (Baja)
          responsable: String.t(),
          estado: :pendiente | :evaluada | :asignada | :atendida | :cancelada
        }

  @doc """
  Convierte la estructura a un mapa de cadenas para guardar en el archivo JSON.
  """
  def a_registro(%__MODULE__{} = necesidad) do
    %{
      "id" => necesidad.id,
      "tipo" => necesidad.tipo,
      "descripcion" => necesidad.descripcion,
      "cantidad" => necesidad.cantidad,
      "zona" => necesidad.zona,
      "prioridad" => necesidad.prioridad,
      "responsable" => necesidad.responsable,
      "estado" => Atom.to_string(necesidad.estado)
    }
  end

  @doc """
  Reconstruye la estructura a partir del mapa leído del disco.
  """
  def de_registro(mapa) do
    %__MODULE__{
      id: mapa["id"],
      tipo: mapa["tipo"],
      descripcion: mapa["descripcion"],
      cantidad: mapa["cantidad"],
      zona: mapa["zona"],
      prioridad: mapa["prioridad"],
      responsable: mapa["responsable"],
      # Usamos String.to_atom para soportar los 5 estados nuevos definidos
      estado: String.to_atom(mapa["estado"] || "pendiente")
    }
  end
end
