defmodule Mix.Tasks.Emergencias do
  @shortdoc "Inicia la consola del sistema de coordinación de emergencias"

  @moduledoc """
  Arranca la aplicación (servidores y supervisor) y abre la consola interactiva.

      mix emergencias

  Dentro de la consola se escriben los comandos del sistema (`help` los lista) y
  se termina con `salir`. Los datos se guardan en el directorio configurado en
  `config :emergencias, directorio_datos: ...` (por defecto, `datos/`).

  También se puede alimentar con un archivo de comandos:

      mix emergencias < comandos.txt

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  use Mix.Task

  @impl Mix.Task
  def run(_argumentos) do
    Mix.Task.run("app.start")
    Emergencias.CLI.iniciar()
  end
end
