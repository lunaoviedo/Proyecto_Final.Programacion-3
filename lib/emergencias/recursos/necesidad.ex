defmodule Emergencias.Recursos.Necesidad do
  @moduledoc """
  Estructura inmutable que representa una solicitud de recursos de un albergue.
  """

  @enforce_keys [:id, :codigo_albergue, :recurso_requerido, :cantidad]
  defstruct [:id, :codigo_albergue, :recurso_requerido, :cantidad, estado: :pendiente]

  @type t :: %__MODULE__{
          id: String.t(),
          codigo_albergue: String.t(),
          recurso_requerido: String.t(),
          cantidad: pos_integer(),
          estado: :pendiente | :satisfecha
        }

  @doc """
  Convierte la estructura a un mapa de cadenas para guardar en el archivo JSON.
  """
  def a_registro(%__MODULE__{} = necesidad) do
    %{
      "id" => necesidad.id,
      "codigo_albergue" => necesidad.codigo_albergue,
      "recurso_requerido" => necesidad.recurso_requerido,
      "cantidad" => necesidad.cantidad,
      # Convertimos el átomo de estado a texto para evitar problemas al serializar
      "estado" => Atom.to_string(necesidad.estado)
    }
  end

  @doc """
  Reconstruye la estructura a partir del mapa leído del disco.
  """
  def de_registro(mapa) do
    %__MODULE__{
      id: mapa["id"],
      codigo_albergue: mapa["codigo_albergue"],
      recurso_requerido: mapa["recurso_requerido"],
      cantidad: mapa["cantidad"],
      # String.to_existing_atom es seguro porque :pendiente y :satisfecha ya existen en el sistema
      estado: String.to_existing_atom(mapa["estado"] || "pendiente")
    }
  end
end
