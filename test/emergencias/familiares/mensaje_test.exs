defmodule Emergencias.Familiares.MensajeTest do
  use ExUnit.Case, async: true

  alias Emergencias.Familiares.Mensaje

  @obligatorios %{
    id: "ME001",
    fecha: ~U[2026-11-10 20:00:00Z],
    remitente: "ana",
    destinatario: "luis",
    contenido: "Estoy bien"
  }

  describe "estados/0" do
    test "retorna pendiente y entregado" do
      assert Mensaje.estados() == [:pendiente, :entregado]
    end
  end

  describe "struct" do
    test "con solo los campos obligatorios nace pendiente" do
      mensaje = struct!(Mensaje, @obligatorios)

      assert mensaje.estado == :pendiente
      assert mensaje.estado in Mensaje.estados()
    end

    test "exige todos los campos obligatorios" do
      for campo <- Map.keys(@obligatorios) do
        assert_raise ArgumentError, fn -> struct!(Mensaje, Map.delete(@obligatorios, campo)) end
      end
    end
  end
end
