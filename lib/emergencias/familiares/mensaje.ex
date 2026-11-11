defmodule Emergencias.Familiares.Mensaje do
  @moduledoc """
  Define la estructura de un mensaje entre familiares.

  Un mensaje nace `:pendiente` y pasa a `:entregado` cuando su destinatario lo
  recibe. Las reglas de envío y entrega están en `Emergencias.Familiares.Mensajes`.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  @enforce_keys [:id, :fecha, :remitente, :destinatario, :contenido]
  defstruct [:id, :fecha, :remitente, :destinatario, :contenido, estado: :pendiente]

  @typedoc "Estado de entrega del mensaje."
  @type estado :: :pendiente | :entregado

  @typedoc """
  Mensaje entre familiares.

    * `id`: identificador único del mensaje.
    * `fecha`: instante en que se envió.
    * `remitente` y `destinatario`: nombres de usuario de quien escribe y de quien recibe.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          fecha: DateTime.t(),
          remitente: String.t(),
          destinatario: String.t(),
          contenido: String.t(),
          estado: estado()
        }

  @estados [:pendiente, :entregado]

  @doc """
  Retorna los estados válidos de un mensaje.
  """
  @spec estados() :: [estado()]
  def estados, do: @estados
end
