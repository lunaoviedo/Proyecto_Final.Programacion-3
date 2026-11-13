defmodule Emergencias.Recursos.ServidorNecesidadesTest do
  use ExUnit.Case

  alias Emergencias.Recursos.{ServidorNecesidades, Necesidad}

  setup do
    id = "NEC_TEST_#{System.unique_integer([:positive])}"
    {:ok, id: id}
  end

  test "registrar una necesidad, listarla como pendiente y luego cambiar su estado", %{id: id} do
    necesidad = %Necesidad{
      id: id,
      tipo: "agua",
      descripcion: "Agua potable",
      cantidad: 100,
      asignado: 0,
      zona: "zona_centro",
      prioridad: 1,
      responsable: "voluntario1",
      estado: :pendiente
    }

    assert :ok = ServidorNecesidades.registrar_necesidad(necesidad)

    # Listar usando el filtro de estado como pide el requerimiento
    pendientes = ServidorNecesidades.listar_necesidades(%{estado: :pendiente})
    assert Enum.any?(pendientes, fn n -> n.id == id end)

    # Cambiar estado a asignada
    assert :ok = ServidorNecesidades.cambiar_estado(id, :asignada)

    # Verificar que ya no aparece en las pendientes
    pendientes_actualizadas = ServidorNecesidades.listar_necesidades(%{estado: :pendiente})
    refute Enum.any?(pendientes_actualizadas, fn n -> n.id == id end)
  end
end
