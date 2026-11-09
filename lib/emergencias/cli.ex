defmodule Emergencias.CLI do
  alias Emergencias.Comandos
  alias Emergencias.Usuarios.ServidorSesiones

  def iniciar do
    Util2.mostrar("Sistema de Coordinación de Emergencias. Escribe 'salir' para terminar.", :mensaje)
    ciclo(nil)
  end

  defp ciclo(sesion) do
    sesion
    |> prompt()
    |> Util2.ingresar(:texto)
    |> procesar(sesion)
  end

  defp procesar("", sesion), do: ciclo(sesion)
  defp procesar(linea, sesion) when linea in ["salir", "exit"], do: cerrar(sesion)

  defp procesar(linea, sesion) do
    case Comandos.ejecutar(sesion, linea) do
      {:ok, mensaje, nueva_sesion} ->
        Util2.mostrar(mensaje, :mensaje)
        ciclo(nueva_sesion)

      {:error, mensaje} ->
        Util2.mostrar("✗ " <> mensaje, :error)
        ciclo(sesion)
    end
  end

  defp prompt(nil), do: "> "
  defp prompt(usuario), do: "#{usuario}> "

  defp cerrar(nil), do: :ok

  defp cerrar(sesion) do
    ServidorSesiones.desconectar(sesion)
    :ok
  end
end
