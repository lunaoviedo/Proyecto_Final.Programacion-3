defmodule Emergencias.Recursos.RecursoTest do
  use ExUnit.Case
  alias Emergencias.Recursos.Recurso

  test "a_registro/1 convierte la estructura de Recurso a un mapa para JSON" do
    recurso = %Recurso{
      codigo: "R001",
      nombre: "Agua Embotellada",
      categoria: "hidratacion",
      cantidad: 500,
      unidad: "litros",
      ubicacion: "Bodega Central"
    }

    mapa = Recurso.a_registro(recurso)

    assert mapa["codigo"] == "R001"
    assert mapa["nombre"] == "Agua Embotellada"
    assert mapa["categoria"] == "hidratacion"
    assert mapa["cantidad"] == 500
    assert mapa["unidad"] == "litros"
    assert mapa["ubicacion"] == "Bodega Central"
  end

  test "de_registro/1 reconstruye correctamente la estructura de Recurso desde disco" do
    mapa = %{
      "codigo" => "R002",
      "nombre" => "Carpas",
      "categoria" => "refugio",
      "cantidad" => 20,
      "unidad" => "unidades",
      "ubicacion" => "Bodega Sur"
    }

    recurso = Recurso.de_registro(mapa)

    assert recurso.codigo == "R002"
    assert recurso.nombre == "Carpas"
    assert recurso.cantidad == 20
  end
end
