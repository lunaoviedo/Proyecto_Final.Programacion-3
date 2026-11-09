defmodule Emergencias.Usuarios.Cuentas do
  alias Emergencias.Usuarios.Usuario

  @roles %{
    "ciudadano" => :ciudadano,
    "voluntario" => :voluntario,
    "coordinador" => :coordinador,
    "administrador" => :administrador
  }

   @permisos %{
    ciudadano: [
      :registrar_necesidad, :listar_necesidades, :reportar_persona, :buscar_persona,
      :enviar_mensaje_familiar, :listar_mensajes_familiares, :reportar_mascota, :consultar_zona, :listar_zonas
    ],
    voluntario: [
      :registrar_necesidad, :listar_necesidades, :reportar_persona, :buscar_persona,
      :enviar_mensaje_familiar, :listar_mensajes_familiares, :reportar_mascota,
      :cotejar_mascotas, :registrar_ingreso, :registrar_salida, :consultar_albergue, :consultar_zona, :listar_zonas
    ],
    coordinador: :todo,
    administrador: :todo
  }


   def registrar(usuarios, atributos) do
    with :ok <- validar_usuario(atributos[:usuario]),
         :ok <- validar_clave(atributos[:clave]),
         :ok <- validar_texto(atributos[:nombre_completo], :nombre_completo_invalido),
         :ok <- validar_texto(atributos[:zona], :zona_invalida),
         {:ok, rol} <- interpretar_rol(atributos[:rol]),
         :ok <- verificar_disponible(usuarios, atributos.usuario) do
      nuevo = %Usuario{
        usuario: atributos.usuario,
        hash_clave: calcular_hash(atributos.clave),
        nombre_completo: atributos.nombre_completo,
        rol: rol,
        zona: atributos.zona
      }

      {:ok, Map.put(usuarios, nuevo.usuario, nuevo), nuevo}
    end
  end

  def autenticar(usuarios, usuario, clave) when is_binary(clave) do
    case Map.fetch(usuarios, usuario) do
      {:ok, %Usuario{hash_clave: hash} = encontrado} ->
        if hash == calcular_hash(clave),
        do: {:ok, encontrado},
        else: {:error, :credenciales_invalidas}

      :error -> {:error, :no_encontrado}
    end
  end

  def autenticar(_usuarios, _usuario, _clave), do: {:error, :credenciales_invalidas}

  def conectar(usuarios, usuario, clave, rol, zona) do
    if Map.has_key?(usuarios, usuario) do
      with {:ok, encontrado} <- autenticar(usuarios, usuario, clave) do
        {:ok, usuarios, encontrado, :autenticado}
      end
    else
      atributos = %{usuario: usuario, clave: clave, nombre_completo: usuario, rol: rol, zona: zona}

      with {:ok, usuarios, nuevo} <- registrar(usuarios, atributos) do
        {:ok, usuarios, nuevo, :registrado}
      end
    end
  end

  def puede?(rol, accion) do
    case Map.fetch!(@permisos, rol) do
      :todo -> true
      lista -> accion in lista
    end
  end

  def registrar_actividad(usuarios, usuario, accion) do
  case Map.fetch(usuarios, usuario) do
    {:ok, encontrado} ->
      entrada = %{"fecha" => DateTime.to_iso8601(DateTime.utc_now()), "accion" => accion}

      {:ok,
       Map.put(usuarios, usuario, %{encontrado | actividad: [entrada | encontrado.actividad]})}

    :error ->
      {:error, :no_encontrado}
  end
end

  def a_registro(%Usuario{} = u) do
    %{
      "usuario" => u.usuario,
      "hash_clave" => u.hash_clave,
      "nombre_completo" => u.nombre_completo,
      "rol" => Atom.to_string(u.rol),
      "zona" => u.zona,
      "actividad" => u.actividad
    }
  end

  def de_registro(
        %{
          "usuario" => usuario,
          "hash_clave" => hash,
          "nombre_completo" => nombre,
          "rol" => rol,
          "zona" => zona
        } = registro
      ) do
    with {:ok, rol_atomo} <- interpretar_rol(rol) do
      {:ok,
       %Usuario{
         usuario: usuario,
         hash_clave: hash,
         nombre_completo: nombre,
         rol: rol_atomo,
         zona: zona,
         actividad: Map.get(registro, "actividad", [])
       }}
    end
  end

  def de_registro(_), do: {:error, :registro_invalido}

  defp calcular_hash(clave), do: Base.encode16(:crypto.hash(:sha256, clave), case: :lower)

  defp interpretar_rol(rol) when rol in [:ciudadano, :voluntario, :coordinador, :administrador], do: {:ok, rol}
  defp interpretar_rol(rol) when is_binary(rol) do
    case Map.fetch(@roles, rol) do
      {:ok, atomo} -> {:ok, atomo}
      :error -> {:error, :rol_invalido}
    end
  end
  defp interpretar_rol(_), do: {:error, :rol_invalido}
  defp validar_usuario(u) when is_binary(u) do
    if String.match?(u, ~r/^[a-zA-Z0-9_]{3,20}$/), do: :ok, else: {:error, :usuario_invalido}
  end

  defp validar_usuario(_), do: {:error, :usuario_invalido}

  defp validar_clave(c) when is_binary(c) and byte_size(c) >= 4, do: :ok
  defp validar_clave(_), do: {:error, :clave_invalida}

  defp validar_texto(t, _error) when is_binary(t) and byte_size(t) > 0, do: :ok
  defp validar_texto(_, error), do: {:error, error}

  defp verificar_disponible(usuarios, usuario) do
    if Map.has_key?(usuarios, usuario), do: {:error, :usuario_existente}, else: :ok
  end



end
