defmodule Emergencias.Familiares.PersonaTest do
  use ExUnit.Case, async: true

  alias Emergencias.Familiares.Persona

  @obligatorios %{
    id: "PE001",
    nombre: "Ana Pérez",
    documento: "1094567890",
    edad: 34,
    zona: "zona_norte"
  }

  describe "estados/0" do
    test "retorna los seis estados en el orden del proceso" do
      assert Persona.estados() == [
               :sin_informacion,
               :reportada,
               :localizada,
               :trasladada,
               :en_albergue,
               :reunificada
             ]
    end
  end

  describe "struct" do
    test "con solo los campos obligatorios usa los valores por defecto" do
      persona = struct!(Persona, @obligatorios)

      assert persona.estado == :reportada
      assert persona.historial == []
    end

    test "exige todos los campos obligatorios" do
      for campo <- Map.keys(@obligatorios) do
        assert_raise ArgumentError, fn -> struct!(Persona, Map.delete(@obligatorios, campo)) end
      end
    end

    test "el estado por defecto es uno de los estados válidos" do
      assert struct!(Persona, @obligatorios).estado in Persona.estados()
    end
  end
end
