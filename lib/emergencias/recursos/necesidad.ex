defmodule Emergencias.Recursos.Necesidad do
  @type estado :: :pendiente | :asignada | :en_atencion | :atendida | :cancelada

  defstruct [:id, :tipo, :descripcion, :cantidad, :asignado, :zona, :prioridad, :responsable, :estado]

  def de_registro(mapa) do
    estado_str = mapa["estado"] || "pendiente"

    # Reemplazo de String.to_atom por pattern matching explícito (Punto 8)
    estado_atom =
      case estado_str do
        "pendiente" -> {:ok, :pendiente}
        "asignada" -> {:ok, :asignada}
        "en_atencion" -> {:ok, :en_atencion}
        "atendida" -> {:ok, :atendida}
        "cancelada" -> {:ok, :cancelada}
        _ -> {:error, "Estado desconocido: #{estado_str}"}
      end

    case estado_atom do
      {:ok, estado_valido} ->
        {:ok, %__MODULE__{
          id: mapa["id"],
          tipo: mapa["tipo"],
          descripcion: mapa["descripcion"],
          cantidad: mapa["cantidad"],
          asignado: mapa["asignado"] || 0, # Agregado para el Punto 3
          zona: mapa["zona"],
          prioridad: mapa["prioridad"],
          responsable: mapa["responsable"],
          estado: estado_valido
        }}
      {:error, motivo} ->
        {:error, motivo}
    end
  end

  def a_registro(%__MODULE__{} = necesidad) do
    %{
      "id" => necesidad.id,
      "tipo" => necesidad.tipo,
      "descripcion" => necesidad.descripcion,
      "cantidad" => necesidad.cantidad,
      "asignado" => necesidad.asignado,
      "zona" => necesidad.zona,
      "prioridad" => necesidad.prioridad,
      "responsable" => necesidad.responsable,
      "estado" => to_string(necesidad.estado)
    }
  end
end
