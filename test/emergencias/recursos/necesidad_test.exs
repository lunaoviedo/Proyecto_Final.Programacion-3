defmodule Emergencias.Recursos.NecesidadTest do
  use ExUnit.Case
  alias Emergencias.Recursos.Necesidad

  test "convierte correctamente la estructura a un registro (mapa) para guardar en disco" do
    necesidad = %Necesidad{
      id: "N-123",
      codigo_albergue: "ALB-01",
      recurso_requerido: "Colchones",
      cantidad: 50,
      estado: :pendiente
    }

    # Ejecutamos la función de traducción
    registro = Necesidad.a_registro(necesidad)

    # Verificamos que el mapa resultante tenga las llaves como texto y los valores correctos
    assert registro["id"] == "N-123"
    assert registro["codigo_albergue"] == "ALB-01"
    assert registro["recurso_requerido"] == "Colchones"
    assert registro["cantidad"] == 50
    # Es crucial verificar que el átomo :pendiente se haya convertido a texto "pendiente"
    assert registro["estado"] == "pendiente"
  end

  test "reconstruye correctamente la estructura desde un registro leído de disco" do
    mapa_leido = %{
      "id" => "N-999",
      "codigo_albergue" => "ALB-02",
      "recurso_requerido" => "Mantas",
      "cantidad" => 200,
      "estado" => "satisfecha"
    }

    # Ejecutamos la reconstrucción
    necesidad = Necesidad.de_registro(mapa_leido)

    # Verificamos que vuelva a ser una estructura válida de Elixir
    assert necesidad.id == "N-999"
    assert necesidad.codigo_albergue == "ALB-02"
    assert necesidad.recurso_requerido == "Mantas"
    assert necesidad.cantidad == 200
    # Verificamos que el texto "satisfecha" haya vuelto a ser el átomo :satisfecha
    assert necesidad.estado == :satisfecha
  end

  test "asigna el estado :pendiente por defecto si el disco no lo tiene" do
    mapa_incompleto = %{
      "id" => "N-000",
      "codigo_albergue" => "ALB-03",
      "recurso_requerido" => "Agua",
      "cantidad" => 10
      # Omitimos intencionalmente el estado
    }

    necesidad = Necesidad.de_registro(mapa_incompleto)

    assert necesidad.estado == :pendiente
  end
end
