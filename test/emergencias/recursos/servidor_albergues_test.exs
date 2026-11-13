defmodule Emergencias.Recursos.ServidorAlberguesTest do
  use ExUnit.Case
  alias Emergencias.Recursos.{ServidorAlbergues, Albergue}

  # Esto se ejecuta antes de cada 'test' para darnos un código único
  setup do
    codigo_unico = "TEST-ALB-" <> Integer.to_string(:rand.uniform(100_000))
    Emergencias.Zonas.ServidorZonas.registrar_zona("Zona Norte", "Zona Norte", :medio)
    Emergencias.Zonas.ServidorZonas.registrar_zona("Zona Sur", "Zona Sur", :medio)
    {:ok, codigo: codigo_unico}
  end

  test "registrar un nuevo albergue exitosamente y evitar duplicados", %{codigo: codigo} do
    albergue = %Albergue{
      codigo: codigo,
      nombre: "Albergue de Pruebas",
      zona: "Zona Norte",
      capacidad_maxima: 5
    }

    # Primera vez: debe devolver :ok
    assert :ok == ServidorAlbergues.registrar_albergue(albergue)

    # Segunda vez con el mismo código: debe dar error
    assert {:error, :albergue_ya_existe} == ServidorAlbergues.registrar_albergue(albergue)
  end

  test "controlar el ingreso, salida y limite de capacidad", %{codigo: codigo} do
    albergue = %Albergue{
      codigo: codigo,
      nombre: "Albergue Pequeño",
      zona: "Zona Sur",
      capacidad_maxima: 2 # Solo caben 2 personas
    }

    # Preparamos el albergue
    ServidorAlbergues.registrar_albergue(albergue)

    # 1. Ingreso de dos personas (debe funcionar)
    assert {:ok, 1} == ServidorAlbergues.ingresar_persona(codigo, "DOC-1")
    assert {:ok, 2} == ServidorAlbergues.ingresar_persona(codigo, "DOC-2")

    # 2. Intentar ingresar a una tercera (debe rebotar por sobrecupo)
    assert {:error, :capacidad_excedida} == ServidorAlbergues.ingresar_persona(codigo, "DOC-3")

    # 3. Intentar ingresar a alguien que ya está (debe avisar)
    assert {:error, :persona_ya_ingresada} == ServidorAlbergues.ingresar_persona(codigo, "DOC-1")

    # 4. Salida de una persona (debe dejar ocupación en 1)
    assert {:ok, 1} == ServidorAlbergues.registrar_salida(codigo, "DOC-1")

    # 5. Salida de alguien que no está
    assert {:error, :persona_no_encontrada} == ServidorAlbergues.registrar_salida(codigo, "DOC-99")
  end
end
