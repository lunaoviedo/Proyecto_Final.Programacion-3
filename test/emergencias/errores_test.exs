defmodule Emergencias.ErroresTest do
  use ExUnit.Case, async: true

  alias Emergencias.Errores

  doctest Emergencias.Errores

  test "traduce los errores de recursos, albergues y necesidades" do
    assert Errores.mensaje(:inventario_insuficiente) =~ "inventario"
    assert Errores.mensaje(:capacidad_excedida) =~ "cupos"
    assert Errores.mensaje(:albergue_no_encontrado) == "El albergue no existe."
    assert Errores.mensaje(:necesidad_ya_existe) =~ "necesidad"
  end

  test "traduce los errores de familiares y mascotas" do
    assert Errores.mensaje(:documento_existente) =~ "documento"
    assert Errores.mensaje(:reporte_resuelto) =~ "resuelto"
    assert Errores.mensaje({:filtro_invalido, "x=1"}) == "Filtro inválido: x=1"
  end

  test "los motivos desconocidos no lanzan excepciones" do
    assert Errores.mensaje(:algo_raro) == "Error: :algo_raro"
    assert Errores.mensaje({:otra, 1}) == "Error: {:otra, 1}"
  end

  test "ningún mensaje conocido deja ver un átomo crudo" do
    conocidos = [
      :credenciales_invalidas,
      :no_conectado,
      :no_autorizado,
      :codigo_existente,
      :recurso_ya_existe,
      :recurso_no_encontrado,
      :albergue_ya_existe,
      :persona_ya_ingresada,
      :necesidad_no_encontrada,
      :persona_no_encontrada,
      :destinatario_no_encontrado,
      :tipos_iguales,
      :mensaje_entregado
    ]

    for motivo <- conocidos do
      refute Errores.mensaje(motivo) =~ "Error:", "#{motivo} sin traducir"
    end
  end
end
