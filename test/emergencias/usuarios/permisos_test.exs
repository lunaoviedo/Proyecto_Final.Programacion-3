defmodule Emergencias.Usuarios.PermisosTest do
  use ExUnit.Case, async: true

  alias Emergencias.Usuarios.Cuentas

  describe "necesidades" do
    test "ciudadano y voluntario pueden registrar y listar necesidades" do
      for rol <- [:ciudadano, :voluntario] do
        assert Cuentas.puede?(rol, :gestionar_necesidades), "#{rol} debe registrar necesidades"
        assert Cuentas.puede?(rol, :ver_necesidades), "#{rol} debe listar necesidades"
      end
    end
  end

  describe "albergues" do
    test "el voluntario puede consultar albergues y el ciudadano no" do
      assert Cuentas.puede?(:voluntario, :ver_albergues)
      refute Cuentas.puede?(:ciudadano, :ver_albergues)
    end

    test "el voluntario registra ingresos y salidas, el ciudadano no" do
      assert Cuentas.puede?(:voluntario, :registrar_ingreso)
      assert Cuentas.puede?(:voluntario, :registrar_salida)
      refute Cuentas.puede?(:ciudadano, :registrar_ingreso)
    end
  end

  describe "operaciones de coordinación" do
    test "el resumen global es solo para coordinador y administrador" do
      assert Cuentas.puede?(:coordinador, :ver_resumen)
      assert Cuentas.puede?(:administrador, :ver_resumen)
      refute Cuentas.puede?(:voluntario, :ver_resumen)
      refute Cuentas.puede?(:ciudadano, :ver_resumen)
    end

    test "ciudadano y voluntario no administran recursos ni albergues" do
      for rol <- [:ciudadano, :voluntario],
          accion <- [
            :registrar_recurso,
            :registrar_albergue,
            :transferir_recursos,
            :registrar_zona
          ] do
        refute Cuentas.puede?(rol, accion), "#{rol} no debe poder #{accion}"
      end
    end
  end

  test "todos los roles consultan zonas" do
    for rol <- [:ciudadano, :voluntario, :coordinador, :administrador] do
      assert Cuentas.puede?(rol, :consultar_zona)
      assert Cuentas.puede?(rol, :listar_zonas)
    end
  end
end
