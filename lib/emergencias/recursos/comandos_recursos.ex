defmodule Emergencias.Recursos.ComandosRecursos do
  @moduledoc """
  Procesa los comandos de texto relacionados con el inventario de recursos
  y la gestión de albergues.
  """

  alias Emergencias.Recursos.{ServidorInventario, ServidorAlbergues, Recurso, Albergue}
  alias Emergencias.Usuarios.ServidorSesiones

  @usos %{
    "register_resource" => "register_resource codigo nombre categoria cantidad unidad ubicacion",
    "request_resource" => "request_resource codigo cantidad",
    "register_shelter" => "register_shelter codigo nombre zona capacidad",
    "shelter_checkin" => "shelter_checkin codigo cantidad_personas"
  }

  @doc """
  Intenta ejecutar un comando de recursos. Si el comando no pertenece a este
  módulo, retorna `:no_aplica` para que el sistema intente con otros módulos.
  """

  # Comando: register_resource
  def ejecutar(sesion, "register_resource", [
        codigo,
        nombre,
        categoria,
        cantidad_str,
        unidad,
        ubicacion
      ]) do
    con_permiso(sesion, :registrar_recurso, fn ->
      case Integer.parse(cantidad_str) do
        {cantidad, ""} when cantidad >= 0 ->
          recurso = %Recurso{
            codigo: codigo,
            nombre: nombre,
            categoria: categoria,
            cantidad: cantidad,
            unidad: unidad,
            ubicacion: ubicacion
          }

          ServidorInventario.registrar_recurso(recurso)
          {:ok, "Recurso #{nombre} (#{codigo}) registrado con #{cantidad} #{unidad}.", sesion}

        _ ->
          {:error, "La cantidad debe ser un número entero no negativo."}
      end
    end)
  end

  def ejecutar(_sesion, "register_resource", _args), do: uso("register_resource")

  # Comando: request_resource (Asignación segura)
  def ejecutar(sesion, "request_resource", [codigo, cantidad_str]) do
    con_permiso(sesion, :asignar_recurso, fn ->
      case Integer.parse(cantidad_str) do
        {cantidad, ""} when cantidad > 0 ->
          case ServidorInventario.asignar_recurso(codigo, cantidad) do
            {:ok, cantidad_restante} ->
              {:ok,
               "Se asignaron #{cantidad} unidades del recurso #{codigo}. Restan: #{cantidad_restante}.",
               sesion}

            {:error, :inventario_insuficiente} ->
              {:error, "Inventario insuficiente para el recurso #{codigo}."}

            {:error, :recurso_no_encontrado} ->
              {:error, "El recurso #{codigo} no existe."}
          end

        _ ->
          {:error, "La cantidad a solicitar debe ser un número entero mayor a cero."}
      end
    end)
  end

  def ejecutar(_sesion, "request_resource", _args), do: uso("request_resource")

  # Comando: register_shelter
  def ejecutar(sesion, "register_shelter", [codigo, nombre, zona, capacidad_str]) do
    con_permiso(sesion, :registrar_albergue, fn ->
      case Integer.parse(capacidad_str) do
        {capacidad, ""} when capacidad >= 0 ->
          albergue = %Albergue{
            codigo: codigo,
            nombre: nombre,
            zona: zona,
            capacidad_maxima: capacidad
          }

          ServidorAlbergues.registrar_albergue(albergue)

          {:ok,
           "Albergue #{nombre} (#{codigo}) registrado con capacidad de #{capacidad} personas.",
           sesion}

        _ ->
          {:error, "La capacidad debe ser un número entero no negativo."}
      end
    end)
  end

  def ejecutar(_sesion, "register_shelter", _args), do: uso("register_shelter")

  # Comando: shelter_checkin (Control de capacidad)
  def ejecutar(sesion, "shelter_checkin", [codigo, cantidad_str]) do
    con_permiso(sesion, :ingresar_personas, fn ->
      case Integer.parse(cantidad_str) do
        {cantidad, ""} when cantidad > 0 ->
          case ServidorAlbergues.ingresar_personas(codigo, cantidad) do
            {:ok, nueva_ocupacion} ->
              {:ok,
               "Ingresaron #{cantidad} personas al albergue #{codigo}. Ocupación actual: #{nueva_ocupacion}.",
               sesion}

            {:error, :capacidad_excedida} ->
              {:error, "Capacidad excedida en el albergue #{codigo}."}

            {:error, :albergue_no_encontrado} ->
              {:error, "El albergue #{codigo} no existe."}
          end

        _ ->
          {:error, "La cantidad de personas debe ser un número entero mayor a cero."}
      end
    end)
  end

  def ejecutar(_sesion, "shelter_checkin", _args), do: uso("shelter_checkin")

  # Si no es ninguno de los anteriores, no aplica a este módulo
  def ejecutar(_sesion, _comando, _args), do: :no_aplica

  # Funciones privadas de ayuda

  defp con_permiso(sesion, accion, funcion) do
    case ServidorSesiones.autorizar(sesion, accion) do
      {:ok, _usuario} ->
        case funcion.() do
          {:ok, _mensaje, _sesion} = resultado ->
            ServidorSesiones.registrar_actividad(sesion, Atom.to_string(accion))
            resultado

          error ->
            error
        end

      {:error, motivo} ->
        {:error, "Error de autorización: #{inspect(motivo)}"}
    end
  end

  defp uso(comando), do: {:error, "Uso: " <> Map.fetch!(@usos, comando)}
end
