defmodule Emergencias.CLI do
  @moduledoc """
  Gestiona la interfaz de línea de comandos (CLI) interactiva del sistema de emergencias,
  recibiendo la entrada del usuario y delegando la ejecución de comandos.

  ##informacion del proyecto
  - autor: Simon Lopez E, Luna Sofia Oviedo Rios, David Alejandro Henao Jaramillo
  - fecha: noviembre del 2026
  - licencia: GNU GPL v3
  """
  alias Emergencias.Comandos
  alias Emergencias.Usuarios.ServidorSesiones

  @doc """
  Inicia la interfaz interactiva de la CLI, mostrando el mensaje de bienvenida
  y entrando en el ciclo de ejecución de comandos.
  """
  def iniciar do
    Util2.mostrar(
      "Sistema de Coordinación de Emergencias. " <>
        "Escribe 'help' para ver los comandos y 'salir' para terminar.",
      :mensaje
    )

    ciclo(nil)
  end

  defp ciclo(sesion) do
    case IO.gets(prompt(sesion)) do
      linea when is_binary(linea) -> procesar(String.trim(linea), sesion)
      _fin_de_entrada -> cerrar(sesion)
    end
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

  defp cerrar(nil) do
    Util2.mostrar("Hasta pronto.", :mensaje)
    :ok
  end

  defp cerrar(sesion) do
    ServidorSesiones.desconectar(sesion)
    cerrar(nil)
  end
end
