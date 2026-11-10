defmodule Emergencias.Comandos do
  @moduledoc """

  ##informacion del proyecto
  - autor: Simon Lopez E, Luna Sofia Oviedo Rios, David Alejandro Henao Jaramillo
  - fecha: noviembre del 2026
  - licencia: GNU GPL v3

  Interpreta y ejecuta comandos de texto.

  `ejecutar/2` recibe la sesión actual (el nombre del usuario conectado, o `nil`)
  y la línea escrita. Retorna:

    * `{:ok, mensaje, nueva_sesion}`
    * `{:error, mensaje}`

  ## Cómo agregar comandos del equipo

  Cada integrante crea un módulo con `ejecutar(sesion, comando, args)` que
  retorna `{:ok, mensaje, sesion}`, `{:error, mensaje}` o `:no_aplica` (si el
  comando no es suyo), y lo agrega a `@modulos_equipo`. Para verificar el rol
  debe llamar a `ServidorSesiones.autorizar/2`.
  """

  alias Emergencias.Usuarios.ServidorSesiones
  alias Emergencias.Zonas.ServidorZonas

  @modulos_equipo [Emergencias.Recursos.ComandosRecursos]

  @usos %{
    "connect" => "connect usuario clave tipo zona",
    "register_zone" => "register_zone codigo nombre nivel [afectados]",
    "register_sector" => "register_sector codigo_zona codigo nombre [afectados]",
    "register_point" => "register_point codigo_sector codigo nombre [afectados]",
    "zone_status" => "zone_status codigo_zona",
    "list_zones" => "list_zones [nivel=critico]"
  }

  @doc """
  Interpreta una línea de comandos de texto y la despacha según la sesión activa y los argumentos provistos.
  """
  def ejecutar(sesion, linea) when is_binary(linea) do
    case OptionParser.split(linea) do
      [] -> {:error, "Comando vacío."}
      [comando | args] -> despachar(sesion, comando, args)
    end
  end

  defp despachar(nil, "connect", [usuario, clave, tipo, zona]) do
    case ServidorSesiones.conectar(usuario, clave, tipo, zona) do
      {:ok, _usuario, :registrado} ->
        {:ok, "Usuario #{usuario} registrado y conectado como #{tipo}.", usuario}

      {:ok, _usuario, :autenticado} ->
        {:ok, "Bienvenido de nuevo, #{usuario}.", usuario}

      {:error, motivo} ->
        {:error, mensaje(motivo)}
    end
  end

  defp despachar(nil, "connect", _args), do: uso("connect")

  defp despachar(sesion, "connect", _args),
    do: {:error, "Ya hay una sesión activa (#{sesion}). Usa disconnect primero."}

  defp despachar(nil, _comando, _args),
    do: {:error, "Debes conectarte primero: connect usuario clave tipo zona"}

  defp despachar(sesion, "disconnect", []) do
    case ServidorSesiones.desconectar(sesion) do
      :ok -> {:ok, "Sesión de #{sesion} cerrada.", nil}
      {:error, motivo} -> {:error, mensaje(motivo)}
    end
  end

  defp despachar(sesion, "register_zone", [codigo, nombre, nivel | resto])
       when length(resto) <= 1 do
    con_permiso(sesion, :registrar_zona, fn ->
      with {:ok, afectados} <- afectados(resto),
           {:ok, zona} <- ServidorZonas.registrar_zona(codigo, nombre, nivel, afectados) do
        {:ok, "Zona #{zona.nombre} (#{zona.codigo}) registrada con nivel #{zona.nivel}.", sesion}
      else
        {:error, motivo} -> {:error, mensaje(motivo)}
      end
    end)
  end

  defp despachar(sesion, "register_sector", [codigo_zona, codigo, nombre | resto])
       when length(resto) <= 1 do
    con_permiso(sesion, :registrar_sector, fn ->
      with {:ok, afectados} <- afectados(resto),
           {:ok, sector} <- ServidorZonas.registrar_sector(codigo_zona, codigo, nombre, afectados) do
        {:ok, "Sector #{sector.nombre} (#{sector.codigo}) agregado a la zona #{codigo_zona}.",
         sesion}
      else
        {:error, motivo} -> {:error, mensaje(motivo)}
      end
    end)
  end

  defp despachar(sesion, "register_point", [codigo_sector, codigo, nombre | resto])
       when length(resto) <= 1 do
    con_permiso(sesion, :registrar_punto, fn ->
      with {:ok, afectados} <- afectados(resto),
           {:ok, punto} <- ServidorZonas.registrar_punto(codigo_sector, codigo, nombre, afectados) do
        {:ok, "Punto #{punto.nombre} (#{punto.codigo}) agregado al sector #{codigo_sector}.",
         sesion}
      else
        {:error, motivo} -> {:error, mensaje(motivo)}
      end
    end)
  end

  defp despachar(sesion, "zone_status", [codigo]) do
    con_permiso(sesion, :consultar_zona, fn ->
      case ServidorZonas.estado_zona(codigo) do
        {:ok, resumen} -> {:ok, formatear_resumen(resumen), sesion}
        {:error, motivo} -> {:error, mensaje(motivo)}
      end
    end)
  end

  defp despachar(sesion, "list_zones", []),
    do: listar_zonas(sesion, fn _zona -> true end)

  defp despachar(sesion, "list_zones", ["nivel=" <> nivel]),
    do: listar_zonas(sesion, &(Atom.to_string(&1.nivel) == nivel))

  defp despachar(_sesion, comando, _args) when is_map_key(@usos, comando),
    do: uso(comando)

  defp despachar(sesion, comando, args), do: delegar(@modulos_equipo, sesion, comando, args)

  defp listar_zonas(sesion, filtro) do
    con_permiso(sesion, :listar_zonas, fn ->
      zonas = Util2.aplicar_filtro(ServidorZonas.listar_zonas(), filtro)

      case zonas do
        [] ->
          {:ok, "No hay zonas que mostrar.", sesion}

        _ ->
          texto =
            zonas
            |> Util2.ordenar(:asc, &rango_nivel(&1.nivel))
            |> Util2.convertir_coleccion_mensaje(&" - #{&1.codigo}: #{&1.nombre} (#{&1.nivel})\n")
            |> Enum.join()
            |> String.trim_trailing()

          {:ok, texto, sesion}
      end
    end)
  end

  defp rango_nivel(:critico), do: 0
  defp rango_nivel(:alto), do: 1
  defp rango_nivel(:medio), do: 2
  defp rango_nivel(:bajo), do: 3

  defp delegar([], _sesion, comando, _args), do: {:error, "Comando desconocido: #{comando}"}

  defp delegar([modulo | resto], sesion, comando, args) do
    case modulo.ejecutar(sesion, comando, args) do
      :no_aplica -> delegar(resto, sesion, comando, args)
      resultado -> resultado
    end
  end

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
        {:error, mensaje(motivo)}
    end
  end

  defp uso(comando), do: {:error, "Uso: " <> Map.fetch!(@usos, comando)}

  defp afectados([]), do: {:ok, 0}

  defp afectados([texto]) do
    case Integer.parse(texto) do
      {numero, ""} -> {:ok, numero}
      _ -> {:error, :afectados_invalidos}
    end
  end

  defp formatear_resumen(r) do
    sectores =
      Enum.map(r.por_sector, fn s -> "    - #{s.nombre} (#{s.codigo}): #{s.total} afectados" end)

    Enum.join(
      [
        "Zona #{r.nombre} (#{r.codigo}) - nivel #{r.nivel}",
        "  Afectados (acumulado): #{r.total_afectados}",
        "  Sectores: #{r.total_sectores} | Puntos de atención: #{r.total_puntos}"
        | sectores
      ],
      "\n"
    )
  end

  defp mensaje(:credenciales_invalidas), do: "Usuario o contraseña incorrectos."
  defp mensaje(:usuario_invalido), do: "Usuario inválido (3 a 20 letras, números o guion bajo)."
  defp mensaje(:clave_invalida), do: "La contraseña debe tener al menos 4 caracteres."

  defp mensaje(:rol_invalido),
    do: "Tipo de usuario inválido (ciudadano, voluntario, coordinador, administrador)."

  defp mensaje(:zona_invalida), do: "Zona inválida."
  defp mensaje(:ya_conectado), do: "Ese usuario ya tiene una sesión activa."
  defp mensaje(:no_conectado), do: "No hay una sesión activa para ese usuario."
  defp mensaje(:no_autorizado), do: "No tienes permiso para ejecutar este comando."
  defp mensaje(:codigo_invalido), do: "Código inválido."
  defp mensaje(:nombre_invalido), do: "Nombre inválido."
  defp mensaje(:nivel_invalido), do: "Nivel inválido (critico, alto, medio, bajo)."
  defp mensaje(:afectados_invalidos), do: "El número de afectados debe ser un entero no negativo."
  defp mensaje(:codigo_existente), do: "Ese código ya está en uso."
  defp mensaje(:zona_no_encontrada), do: "La zona no existe."
  defp mensaje(:sector_no_encontrado), do: "El sector no existe."
  defp mensaje({:persistencia, motivo}), do: "No se pudo guardar: #{inspect(motivo)}"
  defp mensaje(otro), do: "Error: #{inspect(otro)}"
end
