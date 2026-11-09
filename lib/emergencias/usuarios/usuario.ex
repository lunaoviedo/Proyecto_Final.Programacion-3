defmodule Emergencias.Usuarios.Usuario do
@moduledoc """
  Se define la estructura de datos y los tipos asociados a los usuarios del sistema.
  ##informacion del proyecto
  - autor: Simon Lopez E, Luna Sofia Oviedo Rios, David Alejandro Henao Jaramillo
  - fecha: noviembre del 2026
  - licencia: GNU GPL v3
  """
  @enforce_keys [:usuario, :hash_clave, :nombre_completo, :rol, :zona]
  defstruct [:usuario, :hash_clave, :nombre_completo, :rol, :zona, actividad: []]

  @type rol :: :ciudadano | :voluntario | :coordinador | :administrador

  @type t :: %__MODULE__{
          usuario: String.t(),
          hash_clave: String.t(),
          nombre_completo: String.t(),
          rol: rol(),
          zona: String.t(),
          actividad: [map()]
        }
end
