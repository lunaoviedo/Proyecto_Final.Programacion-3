defmodule Emergencias.Recursos.Albergue do
  @moduledoc """
  Define la estructura inmutable de un albergue en el sistema de emergencias.

  Mantiene el registro de la capacidad máxima y la ocupación actual para
  facilitar el control de cupos y evitar el sobrecupo.
  """

  # Obligamos a que estos datos se proporcionen siempre al crear el albergue
  @enforce_keys [:codigo, :nombre, :zona, :capacidad_maxima]

  # Definimos las claves. La ocupación inicial siempre será 0 por defecto.
  defstruct [
    :codigo,
    :nombre,
    :zona,
    :capacidad_maxima,
    ocupacion: []
  ]

  @typedoc """
  Tipo de datos para un Albergue.
  Garantiza mediante tipos que la capacidad y ocupación sean enteros no negativos.
  """
  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          zona: String.t(),
          capacidad_maxima: non_neg_integer(),
          ocupacion: [String.t()] # Lista de identificadores de personas o grupos alojados
        }


  @doc """
  Convierte la estructura Albergue en un mapa de cadenas para la persistencia JSON.
  """
  def a_registro(%__MODULE__{} = albergue) do
    %{
      "codigo" => albergue.codigo,
      "nombre" => albergue.nombre,
      "zona" => albergue.zona,
      "capacidad_maxima" => albergue.capacidad_maxima,
      "ocupacion" => albergue.ocupacion
    }
  end

  @doc """
  Reconstruye la estructura Albergue a partir de un mapa de cadenas cargado del disco.
  """
  def de_registro(mapa) do
    %__MODULE__{
      codigo: mapa["codigo"],
      nombre: mapa["nombre"],
      zona: mapa["zona"],
      capacidad_maxima: mapa["capacidad_maxima"],
      # Si por algún motivo no hay ocupación en el archivo, iniciamos con lista vacía
      ocupacion: mapa["ocupacion"] || []
    }
  end
  
end
