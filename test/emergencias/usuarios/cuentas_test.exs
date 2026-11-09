defmodule Emergencias.Usuarios.CuentasTest do
  use ExUnit.Case, async: true
  alias Emergencias.Usuarios.Cuentas

  test "conectar registra automáticamente si el usuario no existe" do
    assert {:ok, usuarios, usuario, :registrado} =
             Cuentas.conectar(%{}, "laura", "1234", "coordinador", "centro")

    assert usuario.rol == :coordinador
    assert Map.has_key?(usuarios, "laura")
  end

  test "conectar valida la clave si el usuario ya existe" do
    {:ok, usuarios, _, _} = Cuentas.conectar(%{}, "laura", "1234", "coordinador", "centro")

    assert {:ok, _, _, :autenticado} = Cuentas.conectar(usuarios, "laura", "1234", "coordinador", "centro")

    assert {:error, :credenciales_invalidas} =
             Cuentas.conectar(usuarios, "laura", "xxxx", "coordinador", "centro")
  end

  test "rechaza un rol inválido" do
    assert {:error, :rol_invalido} = Cuentas.conectar(%{}, "pedro", "1234", "alien", "centro")
  end

  test "rechaza usuario y clave inválidos" do
    assert {:error, :usuario_invalido} = Cuentas.conectar(%{}, "a", "1234", "ciudadano", "centro")
    assert {:error, :clave_invalida} = Cuentas.conectar(%{}, "pedro", "12", "ciudadano", "centro")
  end

  test "permisos por rol" do
    refute Cuentas.puede?(:ciudadano, :registrar_zona)
    assert Cuentas.puede?(:administrador, :registrar_zona)
    assert Cuentas.puede?(:coordinador, :registrar_necesidad)
  end

  test "a_registro y de_registro son inversas" do
    {:ok, _, usuario, _} = Cuentas.conectar(%{}, "laura", "1234", "coordinador", "centro")
    assert {:ok, ^usuario} = usuario |> Cuentas.a_registro() |> Cuentas.de_registro()
  end
end
