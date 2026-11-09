defmodule Emergencias.Usuarios.Usuario do
  @moduledoc "Usuario del sistema de coordinación de emergencias."

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
