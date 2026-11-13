defmodule Emergencias.Recursos.NecesidadTest do
  use ExUnit.Case
  alias Emergencias.Recursos.Necesidad

  test "convierte correctamente la estructura a un registro (mapa) para guardar en disco" do
    necesidad = %Necesidad{
      id: "N1",
      tipo: "agua",
      descripcion: "Agua potable",
      cantidad: 50,
      asignado: 0,
      zona: "zona_norte",
      prioridad: 2,
      responsable: "voluntario2",
      estado: :pendiente
    }

    registro = Necesidad.a_registro(necesidad)

    assert registro["id"] == "N1"
    assert registro["tipo"] == "agua"
    assert registro["estado"] == "pendiente"
  end
end
