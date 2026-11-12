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

  test "transferir un recurso existente y manejar errores de recursos inexistentes", %{codigo: codigo} do
    recurso = %Recurso{
      codigo: codigo,
      nombre: "Linternas",
      categoria: "herramientas",
      cantidad: 20,
      unidad: "unidades",
      ubicacion: "Bodega Sur"
    }

    ServidorInventario.registrar_recurso(recurso)

    # Transferencia válida
    assert :ok == ServidorInventario.transferir_recurso(codigo, "Albergue Norte")

    # Transferencia de un código inventado
    assert {:error, :recurso_no_encontrado} == ServidorInventario.transferir_recurso("FALSO-999", "Albergue Este")
  end
end
