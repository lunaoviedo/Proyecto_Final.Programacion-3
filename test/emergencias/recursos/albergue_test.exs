defmodule Emergencias.Recursos.AlbergueTest do
  use ExUnit.Case
  alias Emergencias.Recursos.Albergue

  test "a_registro/1 convierte la estructura de Albergue a un mapa" do
    albergue = %Albergue{
      codigo: "A-100",
      nombre: "Polideportivo Central",
      zona: "Centro",
      capacidad_maxima: 150,
      # Simulamos que ya ingresaron dos personas por su documento
      ocupacion: ["101010", "202020"]
    }

    mapa = Albergue.a_registro(albergue)

    assert mapa["codigo"] == "A-100"
    assert mapa["capacidad_maxima"] == 150
    assert mapa["ocupacion"] == ["101010", "202020"]
  end

  test "de_registro/1 reconstruye la estructura de Albergue manteniendo la ocupación" do
    mapa = %{
      "codigo" => "A-101",
      "nombre" => "Colegio Norte",
      "zona" => "Norte",
      "capacidad_maxima" => 300,
      "ocupacion" => ["999999"]
    }

    albergue = Albergue.de_registro(mapa)

    assert albergue.codigo == "A-101"
    assert albergue.capacidad_maxima == 300
    assert albergue.ocupacion == ["999999"]
  end

  test "de_registro/1 inicializa la ocupación vacía si el mapa no la incluye" do
    mapa = %{
      "codigo" => "A-102",
      "nombre" => "Escuela Sur",
      "zona" => "Sur",
      "capacidad_maxima" => 50
    }

    albergue = Albergue.de_registro(mapa)

    assert albergue.ocupacion == []
  end
end
