defmodule Emergencias.ProgramadorResumen do
  use GenServer
  require Logger
  alias Emergencias.Informes

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{})
  end

  @impl true
  def init(estado) do
    programar_siguiente_ejecucion()
    {:ok, estado}
  end

  @impl true
  def handle_info(:ejecutar_resumen, estado) do
    Logger.info("Ejecutando resumen diario automático...")

    # Genera y formatea el resumen global
    resumen_texto = Informes.global()

    # Imprime en la consola
    IO.puts("\n\e[34m=== RESUMEN DIARIO AUTOMÁTICO ===\e[0m\n")
    IO.puts(resumen_texto)
    IO.puts("\n=================================\n")

    # Vuelve a programar
    programar_siguiente_ejecucion()

    {:noreply, estado}
  end

  defp programar_siguiente_ejecucion() do
    ahora = DateTime.utc_now()

    # Calcula la próxima medianoche
    manana = Date.add(ahora |> DateTime.to_date(), 1)
    proxima_medianoche = DateTime.new!(manana, ~T[00:00:00], "Etc/UTC")

    # Diferencia en milisegundos hasta la medianoche
    milisegundos = DateTime.diff(proxima_medianoche, ahora, :millisecond)

    # Programa la ejecución
    Process.send_after(self(), :ejecutar_resumen, milisegundos)
  end
end
