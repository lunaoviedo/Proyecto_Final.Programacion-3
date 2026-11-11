defmodule Emergencias.Mascotas.MascotaTest do
  use ExUnit.Case, async: true

  alias Emergencias.Mascotas.Mascota

  @obligatorios %{
    id: "MA001",
    tipo: :perdida,
    especie: "perro",
    color: "negra",
    tamano: :mediano,
    zona: "zona_norte",
    contacto: "3001234567"
  }

  describe "valores permitidos" do
    test "tipos/0 retorna los tipos de reporte" do
      assert Mascota.tipos() == [:perdida, :encontrada]
    end

    test "estados/0 retorna los estados del ciclo de vida" do
      assert Mascota.estados() == [:activa, :posible_coincidencia, :resuelta]
    end

    test "tamanos/0 retorna los tamaños válidos" do
      assert Mascota.tamanos() == [:pequeno, :mediano, :grande]
    end
  end

  describe "struct" do
    test "con solo los campos obligatorios usa los valores por defecto" do
      mascota = struct!(Mascota, @obligatorios)

      assert mascota.estado == :activa
      assert mascota.caracteristicas == []
      assert mascota.nombre == nil
      assert mascota.coincidencia_con == nil
    end

    test "exige todos los campos obligatorios" do
      for campo <- Map.keys(@obligatorios) do
        assert_raise ArgumentError, fn -> struct!(Mascota, Map.delete(@obligatorios, campo)) end
      end
    end

    test "el estado inicial y los valores de los tipos son consistentes" do
      assert struct!(Mascota, @obligatorios).estado in Mascota.estados()
      assert struct!(Mascota, @obligatorios).tipo in Mascota.tipos()
      assert struct!(Mascota, @obligatorios).tamano in Mascota.tamanos()
    end
  end
end
