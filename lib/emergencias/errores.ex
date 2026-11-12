defmodule Emergencias.Errores do
  @moduledoc """
  Traduce los motivos de error del sistema a mensajes legibles para el usuario.

  Reúne en un solo lugar los errores de todos los módulos (usuarios, zonas,
  recursos, albergues, necesidades, familiares y mascotas), de modo que
  `Emergencias.Comandos` y los módulos de comandos de cada integrante muestren
  mensajes consistentes en vez de átomos como `:inventario_insuficiente`.

  Los motivos desconocidos no lanzan excepciones: se muestran como
  `"Error: ..."` para no ocultar información.

  ## Información del proyecto
  - Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
  - Fecha: Noviembre del 2026
  - Licencia: GNU GPL v3
  """

  @doc """
  Retorna el mensaje en español para un motivo de error.

  ## Ejemplos

      iex> Emergencias.Errores.mensaje(:no_autorizado)
      "No tienes permiso para ejecutar este comando."

      iex> Emergencias.Errores.mensaje({:transicion_invalida, :reportada, :reunificada})
      "Cambio de estado no permitido: reportada -> reunificada."

  """
  @spec mensaje(term()) :: String.t()

  def mensaje(:credenciales_invalidas), do: "Usuario o contraseña incorrectos."
  def mensaje(:usuario_invalido), do: "Usuario inválido (3 a 20 letras, números o guion bajo)."
  def mensaje(:clave_invalida), do: "La contraseña debe tener al menos 4 caracteres."
  def mensaje(:nombre_completo_invalido), do: "Nombre completo inválido."
  def mensaje(:usuario_existente), do: "Ese nombre de usuario ya está registrado."
  def mensaje(:no_encontrado), do: "El usuario no existe."

  def mensaje(:rol_invalido),
    do: "Tipo de usuario inválido (ciudadano, voluntario, coordinador, administrador)."

  def mensaje(:zona_invalida), do: "Zona inválida."
  def mensaje(:ya_conectado), do: "Ese usuario ya tiene una sesión activa."
  def mensaje(:no_conectado), do: "Debes conectarte primero: connect usuario clave tipo zona"
  def mensaje(:no_autorizado), do: "No tienes permiso para ejecutar este comando."


  def mensaje(:codigo_invalido), do: "Código inválido."
  def mensaje(:nombre_invalido), do: "Nombre inválido."
  def mensaje(:nivel_invalido), do: "Nivel inválido (critico, alto, medio, bajo)."
  def mensaje(:afectados_invalidos), do: "El número de afectados debe ser un entero no negativo."
  def mensaje(:codigo_existente), do: "Ese código ya está en uso."
  def mensaje(:zona_no_encontrada), do: "La zona no existe."
  def mensaje(:sector_no_encontrado), do: "El sector no existe."

  def mensaje(:recurso_ya_existe), do: "Ya existe un recurso con ese código."
  def mensaje(:recurso_no_encontrado), do: "El recurso no existe en el inventario."
  def mensaje(:inventario_insuficiente), do: "No hay inventario suficiente para esa cantidad."
  def mensaje(:albergue_ya_existe), do: "Ya existe un albergue con ese código."
  def mensaje(:albergue_no_encontrado), do: "El albergue no existe."
  def mensaje(:capacidad_excedida), do: "El albergue no tiene cupos disponibles."
  def mensaje(:persona_ya_ingresada), do: "La persona ya está registrada en ese albergue."
  def mensaje(:necesidad_ya_existe), do: "Ya existe una necesidad con ese identificador."
  def mensaje(:necesidad_no_encontrada), do: "La necesidad no existe."

  def mensaje(:documento_invalido), do: "Documento inválido (5 a 15 letras o dígitos)."
  def mensaje(:documento_existente), do: "Ya hay una persona registrada con ese documento."
  def mensaje(:edad_invalida), do: "Edad inválida (entero entre 0 y 120)."
  def mensaje(:estado_invalido), do: "Estado inválido."

  def mensaje(:estado_inicial_invalido),
    do: "El estado inicial debe ser reportada o sin_informacion."

  def mensaje(:persona_no_encontrada), do: "No se encontró a la persona."
  def mensaje(:persona_reunificada), do: "El caso de la persona ya está cerrado (reunificada)."

  def mensaje({:transicion_invalida, actual, destino}),
    do: "Cambio de estado no permitido: #{actual} -> #{destino}."

  def mensaje(:remitente_invalido), do: "Remitente inválido."
  def mensaje(:destinatario_invalido), do: "Destinatario inválido."
  def mensaje(:destinatario_no_encontrado), do: "El destinatario no es un usuario registrado."
  def mensaje(:destinatario_es_remitente), do: "No puedes enviarte un mensaje a ti mismo."
  def mensaje(:contenido_invalido), do: "El contenido del mensaje no puede estar vacío."
  def mensaje(:contenido_demasiado_largo), do: "El mensaje es demasiado largo."
  def mensaje(:mensaje_no_encontrado), do: "El mensaje no existe."
  def mensaje(:mensaje_entregado), do: "El mensaje ya fue entregado."

  def mensaje(:id_invalido), do: "Identificador inválido."
  def mensaje(:id_existente), do: "El identificador ya está en uso."
  def mensaje(:tipo_invalido), do: "Tipo inválido (perdida o encontrada)."
  def mensaje(:especie_invalida), do: "Especie inválida."
  def mensaje(:color_invalido), do: "Color inválido."
  def mensaje(:tamano_invalido), do: "Tamaño inválido (pequeno, mediano o grande)."
  def mensaje(:contacto_invalido), do: "Contacto inválido."
  def mensaje(:caracteristicas_invalidas), do: "Rasgos inválidos."
  def mensaje(:reporte_no_encontrado), do: "El reporte no existe."
  def mensaje(:reporte_resuelto), do: "El reporte ya está resuelto."
  def mensaje(:mismo_reporte), do: "Debes indicar dos reportes distintos."
  def mensaje(:tipos_iguales), do: "Los reportes deben ser de tipo contrario."
  def mensaje(:ya_asociado_a_otro), do: "Uno de los reportes ya está asociado a otro."

  def mensaje(:sin_coincidencia_pendiente),
    do: "El reporte no tiene una posible coincidencia pendiente."

  def mensaje(:atributos_invalidos), do: "Los datos del comando no son válidos."
  def mensaje(:filtros_invalidos), do: "Los filtros no son válidos."
  def mensaje({:filtro_invalido, filtro}), do: "Filtro inválido: #{filtro}"
  def mensaje({:persistencia, motivo}), do: "No se pudo guardar: #{inspect(motivo)}"

  def mensaje(otro), do: "Error: #{inspect(otro)}"
end
