defmodule Emergencias.Zonas.ArbolZonasTest do
  use ExUnit.Case, async: true
  alias Emergencias.Zonas.{Zona, Sector, Punto, ArbolZonas}

  setup do
    zona = %Zona{
      codigo: "Z1",
      nombre: "Centro",
      nivel: :critico,
      afectados: 100,
      sectores: [
        %Sector{
          codigo: "S1",
          nombre: "Sector 1",
          afectados: 50,
          puntos: [
            %Punto{codigo: "P1", nombre: "Punto A", afectados: 10},
            %Punto{codigo: "P2", nombre: "Punto B", afectados: 5}
          ]
        },
        %Sector{codigo: "S2", nombre: "Sector 2", afectados: 20, puntos: []}
      ]
    }

    {:ok, zona: zona}
  end

  test "total_afectados suma todos los niveles", %{zona: zona} do
    assert ArbolZonas.total_afectados(zona) == 185
  end

  test "contar_puntos", %{zona: zona} do
    assert ArbolZonas.contar_puntos(zona) == 2
  end

  test "buscar_nodo en distintos niveles", %{zona: zona} do
    assert {:ok, %Punto{nombre: "Punto B"}} = ArbolZonas.buscar_nodo(zona, "P2")
    assert {:ok, %Sector{nombre: "Sector 2"}} = ArbolZonas.buscar_nodo(zona, "S2")
    assert :error = ArbolZonas.buscar_nodo(zona, "XX")
  end

  test "rutas", %{zona: zona} do
    assert "Centro > Sector 1 > Punto A" in ArbolZonas.rutas(zona)
  end
end
