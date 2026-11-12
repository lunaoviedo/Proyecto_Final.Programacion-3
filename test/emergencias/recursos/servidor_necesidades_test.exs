defmodule Emergencias.Recursos.ServidorNecesidadesTest do
  use ExUnit.Case
  alias Emergencias.Recursos.{ServidorNecesidades, Necesidad}

  setup do
    id_unico = "NEC-" <> Integer.to_string(:rand.uniform(100_000))
    {:ok, id: id_unico}
  end

  test "registrar una necesidad, listarla como pendiente y luego satisfacerla", %{id: id} do
    necesidad = %Necesidad{
      id: id,
      codigo_albergue: "ALB-01",
      recurso_requerido: "Agua Potable",
      cantidad: 100
    }

    # 1. Registrar exitosamente
    assert :ok == ServidorNecesidades.registrar_necesidad(necesidad)

    # 2. Evitar duplicados
    assert {:error, :necesidad_ya_existe} == ServidorNecesidades.registrar_necesidad(necesidad)

    # 3. Validar que aparezca en la lista de pendientes
    pendientes = ServidorNecesidades.listar_pendientes()
    assert Enum.any?(pendientes, fn n -> n.id == id end)

    # 4. Satisfacer la necesidad
    assert :ok == ServidorNecesidades.satisfacer_necesidad(id)

    # 5. Validar que ya NO esté en la lista de pendientes
    pendientes_actualizados = ServidorNecesidades.listar_pendientes()
    refute Enum.any?(pendientes_actualizados, fn n -> n.id == id end)
  end
end
