defmodule Emergencias.Recursos.ComandosRecursosTest do
  use ExUnit.Case
  alias Emergencias.Recursos.ComandosRecursos

  # Preparamos una sesión de prueba genérica
  setup do
    {:ok, sesion: "token_simulado_123"}
  end

  test "retorna error de uso cuando faltan argumentos en register_resource", %{sesion: sesion} do
    # Intentamos mandar el comando pero con un solo argumento en lugar de seis
    resultado = ComandosRecursos.ejecutar(sesion, "register_resource", ["R001"])

    assert {:error, mensaje} = resultado
    assert String.starts_with?(mensaje, "Uso: register_resource")
  end

  test "retorna error de uso en comandos sin argumentos correctos", %{sesion: sesion} do
    # Probamos varios comandos pasándoles listas vacías
    assert {:error, m1} = ComandosRecursos.ejecutar(sesion, "register_shelter", [])
    assert String.starts_with?(m1, "Uso: register_shelter")

    assert {:error, m2} = ComandosRecursos.ejecutar(sesion, "register_need", [])
    assert String.starts_with?(m2, "Uso: register_need")
  end

  test "retorna :no_aplica para comandos que no pertenecen a este módulo", %{sesion: sesion} do
    # Un comando que no está en el mapa de @usos
    assert :no_aplica == ComandosRecursos.ejecutar(sesion, "comando_inventado", [])
  end

  test "el servidor de sesiones bloquea la ejecución si la sesión es inválida", %{sesion: sesion} do
    # Mandamos un comando perfectamente válido
    argumentos = ["R999", "Agua", "hidratacion", "100", "litros", "Bodega"]
    resultado = ComandosRecursos.ejecutar(sesion, "register_resource", argumentos)

    # Como nuestra sesión "token_simulado_123" no existe en el sistema real,
    # la función privada con_permiso/3 debería atraparlo y devolver un error de autorización
    assert match?({:error, _motivo}, resultado)

    # Verificamos que el mensaje mencione la autorización
    {:error, mensaje} = resultado
    assert mensaje =~ "Error de autorización"
  end
end
