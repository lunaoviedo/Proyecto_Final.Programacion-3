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
    "register_entry" => "register_entry codigo documento",
    "register_exit" => "register_exit codigo documento"
  }

  def ejecutar(sesion, "register_resource", [codigo, nombre, categoria, cantidad_str, unidad, ubicacion]) do
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

  def ejecutar(sesion, "register_resource", [codigo, nombre, categoria, cantidad_str, unidad, ubicacion]) do
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

          # Evaluamos la respuesta síncrona
          case ServidorInventario.registrar_recurso(recurso) do
            :ok ->
              {:ok, "Recurso #{nombre} (#{codigo}) registrado con #{cantidad} #{unidad}.", sesion}

            {:error, :recurso_ya_existe} ->
              {:error, "El recurso con código #{codigo} ya existe en el sistema."}
          end

        _ ->
          {:error, "La cantidad debe ser un número entero no negativo."}
      end
    end)
  end

  def ejecutar(_sesion, "request_resource", _args), do: uso("request_resource")

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

          # Ahora manejamos el resultado de la llamada síncrona
          case ServidorAlbergues.registrar_albergue(albergue) do
            :ok ->
              {:ok, "Albergue #{nombre} (#{codigo}) registrado con capacidad de #{capacidad} personas.", sesion}

            {:error, :albergue_ya_existe} ->
              {:error, "El albergue con código #{codigo} ya existe."}
          end

        _ ->
          {:error, "La capacidad debe ser un número entero no negativo."}
      end
    end)
  end

  def ejecutar(_sesion, "register_shelter", _args), do: uso("register_shelter")

  def ejecutar(sesion, "register_entry", [codigo, documento]) do
    # Permiso corregido para coincidir con la configuración del voluntario
    con_permiso(sesion, :registrar_ingreso, fn ->
      case ServidorAlbergues.ingresar_persona(codigo, documento) do
        {:ok, nueva_ocupacion} ->
          {:ok, "Persona #{documento} ingresada al albergue #{codigo}. Ocupación actual: #{nueva_ocupacion}.", sesion}

        {:error, :capacidad_excedida} ->
          {:error, "Capacidad excedida en el albergue #{codigo}."}

        {:error, :albergue_no_encontrado} ->
          {:error, "El albergue #{codigo} no existe."}

        {:error, :persona_ya_ingresada} ->
          {:error, "La persona con documento #{documento} ya se encuentra registrada en este albergue."}
      end
    end)
  end

  def ejecutar(_sesion, "register_entry", _args), do: uso("register_entry")

  def ejecutar(sesion, "register_exit", [codigo, documento]) do
    con_permiso(sesion, :registrar_salida, fn ->
      case ServidorAlbergues.registrar_salida(codigo, documento) do
        {:ok, nueva_ocupacion} ->
          {:ok, "Persona #{documento} salió del albergue #{codigo}. Ocupación actual: #{nueva_ocupacion}.", sesion}

        {:error, :albergue_no_encontrado} ->
          {:error, "El albergue #{codigo} no existe."}

        {:error, :persona_no_encontrada} ->
          {:error, "La persona con documento #{documento} no está en este albergue."}
      end
    end)
  end

  def ejecutar(_sesion, "register_exit", _args), do: uso("register_exit")

  def ejecutar(_sesion, _comando, _args), do: :no_aplica

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
