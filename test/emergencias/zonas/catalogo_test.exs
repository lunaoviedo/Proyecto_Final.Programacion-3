defmodule Emergencias.Zonas.CatalogoTest do
  use ExUnit.Case, async: true
  alias Emergencias.Zonas.Catalogo

  defp catalogo_base do
    {:ok, z, _} = Catalogo.registrar_zona(%{}, "Z1", "Centro", "critico", 100)
    {:ok, z, _} = Catalogo.registrar_sector(z, "Z1", "S1", "Sector 1", 50)
    {:ok, z, _} = Catalogo.registrar_punto(z, "S1", "P1", "Punto A", 10)
    z
  end

  test "registra zona, sector y punto, y calcula el resumen" do
    {:ok, zona} = Catalogo.obtener_zona(catalogo_base(), "Z1")
    resumen = Catalogo.resumen(zona)

    assert resumen.total_afectados == 160
    assert resumen.total_sectores == 1
    assert resumen.total_puntos == 1
    assert [%{codigo: "S1", total: 60}] = resumen.por_sector
  end

  test "rechaza códigos repetidos en cualquier nivel" do
    zonas = catalogo_base()
    assert {:error, :codigo_existente} = Catalogo.registrar_zona(zonas, "Z1", "Otra", "alto")
    assert {:error, :codigo_existente} = Catalogo.registrar_sector(zonas, "Z1", "P1", "X")
    assert {:error, :codigo_existente} = Catalogo.registrar_punto(zonas, "S1", "S1", "X")
  end

  test "valida nivel, afectados y existencia de padres" do
    assert {:error, :nivel_invalido} = Catalogo.registrar_zona(%{}, "Z1", "Centro", "gigante")
    assert {:error, :afectados_invalidos} = Catalogo.registrar_zona(%{}, "Z1", "Centro", "alto", -5)
    assert {:error, :zona_no_encontrada} = Catalogo.registrar_sector(%{}, "ZZ", "S1", "X")
    assert {:error, :sector_no_encontrado} = Catalogo.registrar_punto(catalogo_base(), "SS", "P9", "X")
  end

  test "a_registro y de_registro son inversas" do
    {:ok, zona} = Catalogo.obtener_zona(catalogo_base(), "Z1")
    assert {:ok, ^zona} = zona |> Catalogo.a_registro() |> Catalogo.de_registro()
  end
end
