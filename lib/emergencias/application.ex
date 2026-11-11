defmodule Emergencias.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Emergencias.Usuarios.ServidorSesiones,
      Emergencias.Zonas.ServidorZonas,
      Emergencias.Recursos.ServidorInventario,
      Emergencias.Recursos.ServidorAlbergues,
      Emergencias.Mascotas.ServidorMascotas,
      Emergencias.Familiares.ServidorFamiliares
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Emergencias.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
