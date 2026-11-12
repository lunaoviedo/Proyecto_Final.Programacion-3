defmodule Emergencias.Comunidad.ComandosComunidadTest do
  use ExUnit.Case, async: false

  alias Emergencias.Comandos
  alias Emergencias.Comunidad.ComandosComunidad
  alias Emergencias.Usuarios.ServidorSesiones

  # Los servidores de la aplicación conservan sus datos entre ejecuciones, por lo
  # que cada prueba usa usuarios, zonas y documentos con valores únicos.
  defp unico(prefijo) do
    "#{prefijo}#{System.system_time(:microsecond)}#{rem(System.unique_integer([:positive]), 100)}"
  end

  defp documento do
    sufijo = rem(System.system_time(:microsecond), 100_000_000_000)

    "D" <>
      String.pad_leading(Integer.to_string(sufijo), 11, "0") <>
      Integer.to_string(rem(System.unique_integer([:positive]), 10))
  end

  defp conectar(rol) do
    usuario = unico("u")
    {:ok, _, ^usuario} = Comandos.ejecutar(nil, "connect #{usuario} 1234 #{rol} centro")
    on_exit(fn -> ServidorSesiones.desconectar(usuario) end)
    usuario
  end

  defp crear_zona(coordinador) do
    zona = unico("Z")
    {:ok, _, _} = Comandos.ejecutar(coordinador, "register_zone #{zona} Prueba alto")
    zona
  end

  defp identificador(mensaje, expresion), do: expresion |> Regex.run(mensaje) |> hd()

  defp reportar(sesion, tipo, zona, color, nombre) do
    linea =
      ~s(report_pet #{tipo} perro #{color} mediano #{zona} 3001234567 #{nombre} "collar rojo")

    {:ok, mensaje, _} = Comandos.ejecutar(sesion, linea)
    identificador(mensaje, ~r/MA\d+/)
  end

  # Registra una persona y retorna su documento, que es el destinatario de los mensajes.
  defp persona_registrada(sesion, zona) do
    doc = documento()
    {:ok, _, _} = Comandos.ejecutar(sesion, "report_person Andres #{doc} 28 #{zona} localizada")
    doc
  end

  describe "report_pet y list_pets" do
    test "registra un reporte y lo consulta por zona, especie y estado" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)

      linea =
        ~s(report_pet perdida Perro Negro mediano #{zona} 3001234567 Luna "collar rojo,cojea")

      assert {:ok, mensaje, ^coordinador} = Comandos.ejecutar(coordinador, linea)
      id = identificador(mensaje, ~r/MA\d+/)

      assert {:ok, listado, _} = Comandos.ejecutar(coordinador, "list_pets zona=#{zona}")
      assert listado =~ id
      assert listado =~ "collar rojo, cojea"

      assert {:ok, _, _} = Comandos.ejecutar(coordinador, "list_pets zona=#{zona} especie=perro")

      assert {:ok, "No hay reportes que mostrar.", _} =
               Comandos.ejecutar(coordinador, "list_pets zona=#{zona} estado=resuelta")
    end

    test "un ciudadano puede reportar una mascota" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)
      ciudadano = conectar("ciudadano")

      assert {:ok, mensaje, ^ciudadano} =
               Comandos.ejecutar(
                 ciudadano,
                 "report_pet encontrada gato gris pequeno #{zona} 3000000000"
               )

      assert mensaje =~ "registrado"
    end

    test "con - se omiten el nombre y los rasgos" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)

      assert {:ok, _, _} =
               Comandos.ejecutar(
                 coordinador,
                 "report_pet perdida perro cafe grande #{zona} 3001112233 - -"
               )

      assert {:ok, listado, _} = Comandos.ejecutar(coordinador, "list_pets zona=#{zona}")
      assert listado =~ "sin nombre"
      assert listado =~ "sin rasgos"
    end

    test "rechaza datos inválidos" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)

      assert {:error, mensaje} =
               Comandos.ejecutar(coordinador, "report_pet perdida perro negro enorme #{zona} 300")

      assert mensaje =~ "Tamaño inválido"

      assert {:error, "La zona no existe."} =
               Comandos.ejecutar(
                 coordinador,
                 "report_pet perdida perro negro mediano #{unico("X")} 300"
               )

      assert {:error, mensaje} =
               Comandos.ejecutar(
                 coordinador,
                 "report_pet volando perro negro mediano #{zona} 300"
               )

      assert mensaje =~ "Tipo inválido"
    end

    test "rechaza una cantidad incorrecta de argumentos" do
      coordinador = conectar("coordinador")

      assert {:error, "Uso: report_pet" <> _} =
               Comandos.ejecutar(coordinador, "report_pet perdida perro")

      assert {:error, "Uso: report_pet" <> _} =
               Comandos.ejecutar(coordinador, "report_pet a b c d e f g h i")
    end

    test "rechaza filtros inválidos" do
      coordinador = conectar("coordinador")

      assert {:error, "Filtro inválido: color=rojo"} =
               Comandos.ejecutar(coordinador, "list_pets color=rojo")

      assert {:error, "Filtro inválido: zona"} = Comandos.ejecutar(coordinador, "list_pets zona")

      assert {:error, "Estado inválido."} =
               Comandos.ejecutar(coordinador, "list_pets estado=volando")
    end
  end

  describe "coincidencias de mascotas" do
    test "flujo completo: cotejar, asociar, descartar y confirmar" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)
      color = unico("c")
      nombre = unico("n")

      perdida = reportar(coordinador, "perdida", zona, color, nombre)
      encontrada = reportar(coordinador, "encontrada", zona, color, nombre)

      assert {:ok, texto, _} = Comandos.ejecutar(coordinador, "match_pets")
      assert texto =~ "#{perdida} (perdida) ~ #{encontrada} (encontrada)"

      assert {:ok, mensaje, _} =
               Comandos.ejecutar(coordinador, "link_pets #{perdida} #{encontrada}")

      assert mensaje =~ "posible coincidencia"

      assert {:ok, listado, _} =
               Comandos.ejecutar(
                 coordinador,
                 "list_pets zona=#{zona} estado=posible_coincidencia"
               )

      assert listado =~ perdida
      assert listado =~ encontrada

      assert {:ok, mensaje, _} = Comandos.ejecutar(coordinador, "discard_match #{perdida}")
      assert mensaje =~ "descartada"

      assert {:ok, mensaje, _} =
               Comandos.ejecutar(coordinador, "confirm_match #{perdida} #{encontrada}")

      assert mensaje =~ "confirmada"

      assert {:ok, listado, _} =
               Comandos.ejecutar(coordinador, "list_pets zona=#{zona} estado=resuelta")

      assert listado =~ perdida
      assert listado =~ encontrada
    end

    test "un reporte resuelto no puede cerrarse ni descartarse de nuevo" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)
      perdida = reportar(coordinador, "perdida", zona, unico("c"), unico("n"))
      encontrada = reportar(coordinador, "encontrada", zona, unico("c"), unico("n"))

      assert {:ok, _, _} =
               Comandos.ejecutar(coordinador, "confirm_match #{perdida} #{encontrada}")

      assert {:error, "El reporte ya está resuelto."} =
               Comandos.ejecutar(coordinador, "confirm_match #{perdida} #{encontrada}")

      assert {:error, "El reporte ya está resuelto."} =
               Comandos.ejecutar(coordinador, "discard_match #{perdida}")
    end

    test "rechaza parejas inválidas" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)
      perdida = reportar(coordinador, "perdida", zona, unico("c"), unico("n"))
      otra = reportar(coordinador, "perdida", zona, unico("c"), unico("n"))

      assert {:error, "Los reportes deben ser de tipo contrario."} =
               Comandos.ejecutar(coordinador, "link_pets #{perdida} #{otra}")

      assert {:error, "Debes indicar dos reportes distintos."} =
               Comandos.ejecutar(coordinador, "link_pets #{perdida} #{perdida}")

      assert {:error, "El reporte no existe."} =
               Comandos.ejecutar(coordinador, "link_pets #{perdida} MA999999")

      assert {:error, "El reporte no tiene una posible coincidencia pendiente."} =
               Comandos.ejecutar(coordinador, "discard_match #{perdida}")

      assert {:error, "Uso: link_pets id_a id_b"} =
               Comandos.ejecutar(coordinador, "link_pets #{perdida}")
    end

    test "un voluntario puede cotejar y un ciudadano no" do
      voluntario = conectar("voluntario")
      ciudadano = conectar("ciudadano")

      assert {:ok, _, ^voluntario} = Comandos.ejecutar(voluntario, "match_pets")
      assert {:error, mensaje} = Comandos.ejecutar(ciudadano, "match_pets")
      assert mensaje =~ "permiso"
    end
  end

  describe "personas" do
    test "registra una persona, la busca y consulta su historial" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)
      doc = documento()

      assert {:ok, mensaje, _} =
               Comandos.ejecutar(coordinador, ~s(report_person "Ana Gómez" #{doc} 34 #{zona}))

      id = identificador(mensaje, ~r/PE\d+/)
      assert mensaje =~ "reportada"

      assert {:ok, listado, _} = Comandos.ejecutar(coordinador, "find_person documento=#{doc}")
      assert listado =~ id
      assert listado =~ "Ana Gómez"

      assert {:ok, listado, _} =
               Comandos.ejecutar(coordinador, "find_person nombre=ana zona=#{zona}")

      assert listado =~ id

      assert {:ok, _, _} = Comandos.ejecutar(coordinador, "update_person #{id} localizada")

      assert {:ok, historial, _} = Comandos.ejecutar(coordinador, "person_history #{id}")
      assert historial =~ "reportada"
      assert historial =~ "localizada"
    end

    test "acepta el estado inicial sin_informacion" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)

      assert {:ok, mensaje, _} =
               Comandos.ejecutar(
                 coordinador,
                 "report_person Pedro #{documento()} 40 #{zona} sin_informacion"
               )

      assert mensaje =~ "sin_informacion"
    end

    test "acepta las edades límite 0 y 120 y rechaza 121" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)

      assert {:ok, _, _} =
               Comandos.ejecutar(coordinador, "report_person Bebe #{documento()} 0 #{zona}")

      assert {:ok, _, _} =
               Comandos.ejecutar(coordinador, "report_person Abuelo #{documento()} 120 #{zona}")

      assert {:error, "Edad inválida (entero entre 0 y 120)."} =
               Comandos.ejecutar(coordinador, "report_person Mayor #{documento()} 121 #{zona}")
    end

    test "rechaza datos inválidos" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)

      assert {:error, "Edad inválida" <> _} =
               Comandos.ejecutar(coordinador, "report_person Ana #{documento()} abc #{zona}")

      assert {:error, "Documento inválido" <> _} =
               Comandos.ejecutar(coordinador, "report_person Ana 12 30 #{zona}")

      assert {:error, "Una persona no puede registrarse como reunificada."} =
               Comandos.ejecutar(
                 coordinador,
                 "report_person Ana #{documento()} 30 #{zona} reunificada"
               )

      assert {:error, "La zona no existe."} =
               Comandos.ejecutar(coordinador, "report_person Ana #{documento()} 30 #{unico("X")}")

      assert {:error, "Uso: report_person" <> _} =
               Comandos.ejecutar(coordinador, "report_person Ana")
    end

    test "registra directamente a una persona como localizada y la busca por documento" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)
      doc = documento()

      assert {:ok, mensaje, _} =
               Comandos.ejecutar(coordinador, "report_person Andres #{doc} 28 #{zona} localizada")

      assert mensaje =~ "localizada"

      assert {:ok, listado, _} = Comandos.ejecutar(coordinador, "find_person #{doc}")
      assert listado =~ "Andres"
      assert listado =~ "localizada"

      assert {:ok, "No se encontraron personas.", _} =
               Comandos.ejecutar(coordinador, "find_person NOEXISTE1")
    end

    test "no admite dos personas con el mismo documento" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)
      doc = documento()

      assert {:ok, _, _} = Comandos.ejecutar(coordinador, "report_person Ana #{doc} 30 #{zona}")

      assert {:error, "Ya hay una persona registrada con ese documento."} =
               Comandos.ejecutar(coordinador, "report_person Luis #{doc} 31 #{zona}")
    end

    test "respeta las transiciones de estado y el cierre del caso" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)

      {:ok, mensaje, _} =
        Comandos.ejecutar(coordinador, "report_person Ana #{documento()} 30 #{zona}")

      id = identificador(mensaje, ~r/PE\d+/)

      assert {:error, "Cambio de estado no permitido: reportada -> reunificada."} =
               Comandos.ejecutar(coordinador, "update_person #{id} reunificada")

      assert {:ok, _, _} = Comandos.ejecutar(coordinador, "update_person #{id} localizada")
      assert {:ok, _, _} = Comandos.ejecutar(coordinador, "update_person #{id} reunificada")

      assert {:error, "El caso de la persona ya está cerrado (reunificada)."} =
               Comandos.ejecutar(coordinador, "update_person #{id} reunificada")

      assert {:error, "Estado inválido."} =
               Comandos.ejecutar(coordinador, "update_person #{id} volando")

      assert {:error, "La persona no existe."} =
               Comandos.ejecutar(coordinador, "update_person PE999999 localizada")
    end

    test "una búsqueda sin resultados o con filtros inválidos informa el motivo" do
      coordinador = conectar("coordinador")

      assert {:ok, "No se encontraron personas.", _} =
               Comandos.ejecutar(coordinador, "find_person documento=NOEXISTE1")

      assert {:error, "Filtro inválido: edad=3"} =
               Comandos.ejecutar(coordinador, "find_person edad=3")

      assert {:error, "La persona no existe."} =
               Comandos.ejecutar(coordinador, "person_history PE999999")
    end
  end

  describe "mensajes entre familiares" do
    test "envía un mensaje a un documento y lo entrega al listarlo" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)
      doc = persona_registrada(coordinador, zona)
      familiar = conectar("ciudadano")

      assert {:ok, mensaje, ^familiar} =
               Comandos.ejecutar(
                 familiar,
                 ~s(send_family_message #{doc} "Estoy bien, estoy en el albergue norte")
               )

      assert mensaje =~ "enviado a Andres"
      id = identificador(mensaje, ~r/ME\d+/)

      assert {:ok, recibidos, _} = Comandos.ejecutar(coordinador, "list_family_messages #{doc}")
      assert recibidos =~ id
      assert recibidos =~ "Estoy bien, estoy en el albergue norte"
      assert recibidos =~ "#{familiar} -> #{doc}"
      assert recibidos =~ "(nuevo)"

      assert {:ok, otra_vez, _} = Comandos.ejecutar(coordinador, "list_family_messages #{doc}")
      refute otra_vez =~ "(nuevo)"
      assert otra_vez =~ "(entregado)"
    end

    test "un documento sin mensajes recibe un aviso" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)
      doc = persona_registrada(coordinador, zona)

      assert {:ok, "No hay mensajes para Andres.", ^coordinador} =
               Comandos.ejecutar(coordinador, "list_family_messages #{doc}")
    end

    test "rechaza documentos desconocidos y contenidos inválidos" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)
      doc = persona_registrada(coordinador, zona)

      assert {:error, "La persona no existe."} =
               Comandos.ejecutar(coordinador, "send_family_message NOEXISTE1 Hola")

      assert {:error, "La persona no existe."} =
               Comandos.ejecutar(coordinador, "list_family_messages NOEXISTE1")

      assert {:error, "Uso: send_family_message documento contenido"} =
               Comandos.ejecutar(coordinador, "send_family_message #{doc}")

      assert {:error, "Uso: list_family_messages documento"} =
               Comandos.ejecutar(coordinador, "list_family_messages")

      assert {:error, "El mensaje supera los 500 caracteres."} =
               Comandos.ejecutar(
                 coordinador,
                 "send_family_message #{doc} #{String.duplicate("a", 501)}"
               )
    end

    test "acepta un mensaje de exactamente 500 caracteres" do
      coordinador = conectar("coordinador")
      zona = crear_zona(coordinador)
      doc = persona_registrada(coordinador, zona)

      assert {:ok, _, _} =
               Comandos.ejecutar(
                 coordinador,
                 "send_family_message #{doc} #{String.duplicate("a", 500)}"
               )
    end
  end

  describe "ejecutar/3" do
    test "sin sesión activa pide conectarse" do
      assert {:error, "Debes conectarte primero" <> _} =
               ComandosComunidad.ejecutar(nil, "list_family_messages", ["DOC12345"])
    end

    test "retorna :no_aplica para comandos de otros módulos" do
      assert :no_aplica = ComandosComunidad.ejecutar("alguien", "register_resource", [])
      assert :no_aplica = ComandosComunidad.ejecutar("alguien", "volar", [])
    end
  end
end
