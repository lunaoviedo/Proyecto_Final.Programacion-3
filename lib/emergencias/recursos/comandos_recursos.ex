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
    "register_need" => "register_need id tipo descripcion cantidad zona prioridad responsable",
    "list_needs" => "list_needs [zona:X] [tipo:Y] [prioridad:Z] [estado:W]",
    "pending_needs" => "pending_needs",
    "check_shelter" => "check_shelter codigo",
    "transfer_resource" => "transfer_resource codigo nueva_ubicacion",
    "movement_history" => "movement_history",
    "assign_resource" => "assign_resource id_necesidad codigo_recurso cantidad"
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

  def ejecutar(sesion, "register_need", [id, tipo, descripcion, cantidad_str, zona, prioridad_str, responsable]) do
    con_permiso(sesion, :registrar_necesidad, fn ->
      case {Integer.parse(cantidad_str), Integer.parse(prioridad_str)} do
        {{cantidad, ""}, {prioridad, ""}} when cantidad > 0 ->
          necesidad = %Necesidad{
            id: id,
            tipo: tipo,
            descripcion: descripcion,
            cantidad: cantidad,
            zona: zona,
            prioridad: prioridad,
            responsable: responsable
          }

          case ServidorNecesidades.registrar_necesidad(necesidad) do
            :ok ->
              {:ok, "Necesidad #{id} registrada: #{cantidad} de #{tipo} para la zona #{zona}.", sesion}
            {:error, :necesidad_ya_existe} ->
              {:error, "Ya existe una necesidad con el ID #{id}."}
          end
        _ ->
          {:error, "La cantidad y la prioridad deben ser números enteros."}
      end
    end)
  end

  def ejecutar(_sesion, "register_need", _args), do: uso("register_need")

  def ejecutar(sesion, "list_needs", args) do
    con_permiso(sesion, :listar_necesidades, fn ->
      filtros =
        Enum.reduce(args, %{}, fn arg, acc ->
          case String.split(arg, ":") do
            [clave, valor] ->
              clave_atomo = String.to_existing_atom(clave)
              valor_final = if clave == "estado", do: String.to_existing_atom(valor), else: valor
              Map.put(acc, clave_atomo, valor_final)
            _ -> acc
          end
        end)

      necesidades = ServidorNecesidades.listar_necesidades(filtros)
      formatear_necesidades(necesidades, sesion)
    end)
  end

  def ejecutar(sesion, "pending_needs", []) do
    con_permiso(sesion, :listar_necesidades, fn ->
      pendientes = ServidorNecesidades.listar_necesidades(%{estado: :pendiente})
      formatear_necesidades(pendientes, sesion)
    end)
  end

  def ejecutar(_sesion, "pending_needs", _args), do: uso("pending_needs")

  def ejecutar(sesion, "assign_resource", [id_necesidad, codigo_recurso, cantidad_str]) do
    con_permiso(sesion, :registrar_necesidad, fn ->
      case Integer.parse(cantidad_str) do
        {cantidad, ""} when cantidad > 0 ->
          case ServidorNecesidades.obtener_necesidad(id_necesidad) do
            {:ok, necesidad} ->
              if necesidad.estado in [:atendida, :cancelada] do
                {:error, "La necesidad está #{necesidad.estado} y no puede consumir más recursos."}
              else
                case ServidorInventario.descontar_recurso(codigo_recurso, cantidad) do
                  :ok ->
                    if necesidad.estado == :pendiente, do: ServidorNecesidades.cambiar_estado(id_necesidad, :evaluada)
                    ServidorNecesidades.cambiar_estado(id_necesidad, :asignada)
                    {:ok, "Se asignaron #{cantidad} unidades del recurso #{codigo_recurso} a la necesidad #{id_necesidad}.", sesion}
                  {:error, :stock_insuficiente} ->
                    {:error, "Stock insuficiente en el inventario para el recurso #{codigo_recurso}."}
                  {:error, :recurso_no_encontrado} ->
                    {:error, "El recurso #{codigo_recurso} no existe en el sistema."}
                end
              end
            {:error, :no_encontrada} ->
              {:error, "La necesidad #{id_necesidad} no existe."}
          end
        _ ->
          {:error, "La cantidad debe ser un número entero positivo."}
      end
    end)
  end

  def ejecutar(_sesion, "assign_resource", _args), do: uso("assign_resource")

  # --- COMANDO PARA REVISAR EL ESTADO DE UN ALBERGUE ---

  def ejecutar(sesion, "check_shelter", [codigo]) do
    con_permiso(sesion, :ver_albergues, fn ->
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
        {:error, Emergencias.Errores.mensaje(motivo)}
    end
  end

  defp uso(comando), do: {:error, "Uso: " <> Map.fetch!(@usos, comando)}

  defp formatear_necesidades([], sesion), do: {:ok, "No hay necesidades en esta lista.", sesion}
  defp formatear_necesidades(lista, sesion) do
    lineas =
      Enum.map(lista, fn n ->
        "- [#{n.id}] Zona #{n.zona} requiere #{n.cantidad} #{n.tipo} (Prioridad: #{n.prioridad}, Estado: #{n.estado})"
      end)

    {:ok, Enum.join(lineas, "\n"), sesion}
  end
end
