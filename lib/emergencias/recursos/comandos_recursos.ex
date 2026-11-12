defmodule Emergencias.Recursos.ComandosRecursos do
  @moduledoc """
  Procesa los comandos de texto relacionados con el inventario de recursos
  y la gestión de albergues.
  """

  alias Emergencias.Recursos.{ServidorInventario, ServidorAlbergues, Recurso, Albergue, ServidorNecesidades, Necesidad}
  alias Emergencias.Usuarios.ServidorSesiones

  @usos %{
    "register_resource" => "register_resource codigo nombre categoria cantidad unidad ubicacion",
    "request_resource" => "request_resource codigo cantidad",
    "register_shelter" => "register_shelter codigo nombre zona capacidad",
    "register_entry" => "register_entry codigo documento",
    "register_exit" => "register_exit codigo documento",
    "register_need" => "register_need id codigo_albergue recurso cantidad",
    "list_needs" => "list_needs",
    "pending_needs" => "pending_needs",
    "check_shelter" => "check_shelter codigo",
    "transfer_resource" => "transfer_resource codigo nueva_ubicacion",
    "movement_history" => "movement_history"
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

  def ejecutar(_sesion, "register_resource", _args), do: uso("register_resource")

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

  # --- NUEVOS COMANDOS DE NECESIDADES ---

  def ejecutar(sesion, "register_need", [id, codigo_albergue, recurso, cantidad_str]) do
    con_permiso(sesion, :gestionar_necesidades, fn ->
      case Integer.parse(cantidad_str) do
        {cantidad, ""} when cantidad > 0 ->
          necesidad = %Necesidad{
            id: id,
            codigo_albergue: codigo_albergue,
            recurso_requerido: recurso,
            cantidad: cantidad
          }

          case ServidorNecesidades.registrar_necesidad(necesidad) do
            :ok ->
              {:ok, "Necesidad #{id} registrada: #{cantidad} de #{recurso} para el albergue #{codigo_albergue}.", sesion}
            {:error, :necesidad_ya_existe} ->
              {:error, "Ya existe una necesidad registrada con el ID #{id}."}
          end

        _ ->
          {:error, "La cantidad debe ser un número entero mayor a cero."}
      end
    end)
  end

  def ejecutar(_sesion, "register_need", _args), do: uso("register_need")

  def ejecutar(sesion, "list_needs", []) do
    con_permiso(sesion, :ver_necesidades, fn ->
      necesidades = ServidorNecesidades.listar_necesidades()
      formatear_necesidades(necesidades, sesion)
    end)
  end

  def ejecutar(_sesion, "list_needs", _args), do: uso("list_needs")

  def ejecutar(sesion, "pending_needs", []) do
    con_permiso(sesion, :ver_necesidades, fn ->
      pendientes = ServidorNecesidades.listar_pendientes()
      formatear_necesidades(pendientes, sesion)
    end)
  end

  def ejecutar(_sesion, "pending_needs", _args), do: uso("pending_needs")

  # --- COMANDO PARA REVISAR EL ESTADO DE UN ALBERGUE ---

  def ejecutar(sesion, "check_shelter", [codigo]) do
    con_permiso(sesion, :ver_albergues, fn ->
      # Obtenemos todos los albergues y buscamos el que coincida con el código
      albergues = ServidorAlbergues.obtener_albergues()

      case Enum.find(albergues, fn a -> a.codigo == codigo end) do
        nil ->
          {:error, "El albergue con código #{codigo} no existe."}

        albergue ->
          ocupacion_actual = length(albergue.ocupacion)
          disponible = albergue.capacidad_maxima - ocupacion_actual

          mensaje = """
          --- ESTADO DEL ALBERGUE ---
          Nombre: #{albergue.nombre} (#{albergue.codigo})
          Zona: #{albergue.zona}
          Ocupación: #{ocupacion_actual} / #{albergue.capacidad_maxima}
          Cupos disponibles: #{disponible}
          ---------------------------
          """ |> String.trim()

          {:ok, mensaje, sesion}
      end
    end)
  end

  def ejecutar(_sesion, "check_shelter", _args), do: uso("check_shelter")

  # --- TRANSFERENCIAS E HISTORIAL ---

  def ejecutar(sesion, "transfer_resource", [codigo, nueva_ubicacion]) do
    con_permiso(sesion, :transferir_recursos, fn ->
      case ServidorInventario.transferir_recurso(codigo, nueva_ubicacion) do
        :ok ->
          {:ok, "Recurso #{codigo} transferido exitosamente a #{nueva_ubicacion}.", sesion}
        {:error, :recurso_no_encontrado} ->
          {:error, "El recurso con código #{codigo} no existe en el inventario."}
      end
    end)
  end

  def ejecutar(_sesion, "transfer_resource", _args), do: uso("transfer_resource")

  def ejecutar(sesion, "movement_history", []) do
    con_permiso(sesion, :ver_movimientos, fn ->
      movimientos = ServidorInventario.obtener_historial_movimientos()

      if movimientos == [] do
        {:ok, "No hay movimientos registrados en el historial.", sesion}
      else
        lineas = Enum.map(movimientos, fn m ->
          "#{m["fecha"]} | #{m["accion"]} | Recurso: #{m["codigo_recurso"]} | De: #{m["origen"]} -> A: #{m["destino"]}"
        end)

        {:ok, "--- HISTORIAL DE MOVIMIENTOS ---\n" <> Enum.join(lineas, "\n"), sesion}
      end
    end)
  end

  def ejecutar(_sesion, "movement_history", _args), do: uso("movement_history")

  def ejecutar(_sesion, _comando, _args), do: :no_aplica

  # --- FUNCIONES PRIVADAS AUXILIARES ---

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

  defp formatear_necesidades([], sesion), do: {:ok, "No hay necesidades en esta lista.", sesion}
  defp formatear_necesidades(lista, sesion) do
    lineas =
      Enum.map(lista, fn n ->
        "- [#{n.id}] Albergue #{n.codigo_albergue} requiere #{n.cantidad} #{n.recurso_requerido} (Estado: #{n.estado})"
      end)

    {:ok, Enum.join(lineas, "\n"), sesion}
  end
end
