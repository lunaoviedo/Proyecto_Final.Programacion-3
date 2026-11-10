defmodule Emergencias.Recursos.Recurso do
  @moduledoc """
  Define la estructura inmutable de un recurso en el sistema de emergencias.

  Representa elementos físicos disponibles en centros de acopio o albergues,
  como agua, alimentos o medicamentos.
  """

  # Obligamos a que al crear un recurso, siempre se entreguen estos datos
  @enforce_keys [:codigo, :nombre, :categoria, :cantidad, :unidad, :ubicacion]

  # Definimos las claves que tendrá la estructura
  defstruct [:codigo, :nombre, :categoria, :cantidad, :unidad, :ubicacion]

  @typedoc """
  Especificación de tipos para ayudar a la validación del código y documentación.
  Garantizamos que la cantidad nunca sea un número negativo en el tipo.
  """
  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          # Ej: "agua", "alimentos"
          categoria: String.t(),
          # Validamos que no existan cantidades negativas
          cantidad: non_neg_integer(),
          # Ej: "litros", "kilos"
          unidad: String.t(),
          # Ej: "centro_acopio_1"
          ubicacion: String.t()
        }
end
