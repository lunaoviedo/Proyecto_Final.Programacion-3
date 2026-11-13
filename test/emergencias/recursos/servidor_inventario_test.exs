defmodule Emergencias.Recursos.ServidorInventarioTest do
  use ExUnit.Case
  alias Emergencias.Recursos.{ServidorInventario, Recurso}

  # Generamos un código único antes de cada prueba para evitar choques
  setup do
    codigo_unico = "REC-" <> Integer.to_string(:rand.uniform(100_000))
    {:ok, codigo: codigo_unico}
  end

  test "registrar un recurso nuevo y evitar códigos duplicados", %{codigo: codigo} do
    recurso = %Recurso{
      codigo: codigo,
      nombre: "Kit de Primeros Auxilios",
      categoria: "medico",
      cantidad: 50,
      unidad: "kits",
      ubicacion: "Bodega Central"
    }

    # Primera vez: éxito
    assert :ok == ServidorInventario.registrar_recurso(recurso)

    # Segunda vez: debe dar error por duplicado
    assert {:error, :recurso_ya_existe} == ServidorInventario.registrar_recurso(recurso)
  end

  test "transferir un recurso existente y manejar errores de stock o inexistencia", %{codigo: codigo} do
    codigo_destino = codigo <> "-DEST"

    recurso_origen = %Recurso{
      codigo: codigo,
      nombre: "Linternas",
      categoria: "herramientas",
      cantidad: 20,
      unidad: "unidades",
      ubicacion: "Bodega Sur"
    }

    recurso_destino = %Recurso{
      codigo: codigo_destino,
      nombre: "Linternas",
      categoria: "herramientas",
      cantidad: 5,
      unidad: "unidades",
      ubicacion: "Albergue Norte"
    }

    assert :ok == ServidorInventario.registrar_recurso(recurso_origen)
    assert :ok == ServidorInventario.registrar_recurso(recurso_destino)

    # Transferencia válida de 10 unidades
    assert :ok == ServidorInventario.transferir_recurso(codigo, codigo_destino, 10)

    # Verificamos que las cantidades se actualizaron (20 - 10 = 10 y 5 + 10 = 15)
    recursos = ServidorInventario.listar_recursos()
    assert Enum.find(recursos, &(&1.codigo == codigo)).cantidad == 10
    assert Enum.find(recursos, &(&1.codigo == codigo_destino)).cantidad == 15

    # Errores esperados según la lógica de ServidorInventario
    assert {:error, :origen_no_encontrado} == ServidorInventario.transferir_recurso("FALSO-999", codigo_destino, 5)
    assert {:error, :destino_no_encontrado} == ServidorInventario.transferir_recurso(codigo, "FALSO-DEST", 5)
    assert {:error, :stock_insuficiente} == ServidorInventario.transferir_recurso(codigo, codigo_destino, 50)
  end
end
