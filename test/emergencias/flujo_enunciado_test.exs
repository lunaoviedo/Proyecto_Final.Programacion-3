defmodule Emergencias.FlujoEnunciadoTest do
  @moduledoc """
  Prueba de integración del flujo de ejemplo del enunciado: todo se ejecuta con
  comandos de texto sobre los servidores reales, salvo el conflicto concurrente
  de asignación de recursos, que se provoca directamente sobre el servidor de
  inventario (`ServidorInventario.descontar_recurso/2`).
  """

  use ExUnit.Case, async: false

  alias Emergencias.Comandos
  alias Emergencias.Recursos.ServidorInventario

  # Ejecuta un comando que debe salir bien y retorna {mensaje, sesion}.
  defp ok!(sesion, linea) do
    assert {:ok, mensaje, nueva_sesion} = Comandos.ejecutar(sesion, linea)
    {mensaje, nueva_sesion}
  end

  defp capturar(texto, patron) do
    assert [_, valor] = Regex.run(patron, texto), "no se encontró #{inspect(patron)} en: #{texto}"
    valor
  end

  test "flujo completo: Laura, el agua, Andrés, el mensaje, la mascota y el resumen" do
    # Los datos persisten entre ejecuciones, así que cada identificador es único.
    s = Base.encode16(:crypto.strong_rand_bytes(3))

    laura = "laura" <> s
    voluntario = "vol" <> s
    familiar = "fam" <> s
    andres = "andres" <> s
    zona = "centro" <> s
    sector = "sec" <> s
    albergue = "alb" <> s
    recurso = "rec" <> s
    documento = "DOC" <> s

    # --- Laura se conecta como coordinadora de la zona centro y arma la zona ---
    assert {"Usuario " <> _, ^laura} =
             ok!(nil, "connect #{laura} 1234 coordinador #{zona}")

    ok!(laura, ~s(register_zone #{zona} "Zona Centro" critico 100))
    ok!(laura, ~s(register_sector #{zona} #{sector} "Sector 3" 40))
    ok!(laura, ~s(register_shelter #{albergue} "Albergue Norte" #{zona} 150))

    # --- El centro de acopio registra 50 litros de agua ---
    ok!(laura, "register_resource #{recurso} Agua agua 50 litros #{albergue}")

    # --- Laura (30 L) y un voluntario (25 L) registran necesidades sobre el agua ---
    ok!(laura, ~s(register_need n1#{s} agua "Agua potable" 30 #{zona} 1 #{laura}))
    {_, voluntario} = ok!(nil, "connect #{voluntario} 1234 voluntario #{zona}")
    ok!(voluntario, ~s(register_need n2#{s} agua "Agua potable" 25 #{zona} 2 #{voluntario}))

    # --- Conflicto concurrente: 30 + 25 = 55 > 50, solo una asignación puede confirmarse ---
    cantidades = [30, 25]

    resultados =
      cantidades
      |> Enum.map(fn cantidad ->
        Task.async(fn -> ServidorInventario.descontar_recurso(recurso, cantidad) end)
      end)
      |> Task.await_many()

    # descontar_recurso/2 devuelve :ok (sin el restante): se deduce de lo descontado
    assert [{descontado, :ok}] =
             cantidades |> Enum.zip(resultados) |> Enum.filter(&match?({_, :ok}, &1))

    assert Enum.count(resultados, &(&1 == {:error, :stock_insuficiente})) == 1

    restante = 50 - descontado
    assert restante in [20, 25]

    inventario = Enum.find(ServidorInventario.listar_recursos(), &(&1.codigo == recurso))
    assert inventario.cantidad == restante

    # --- Un ciudadano registra a Andrés como persona localizada en el albergue ---
    {_, andres_sesion} = ok!(nil, "connect #{andres} 1234 ciudadano #{zona}")
    {msg, _} = ok!(andres_sesion, "report_person Andres #{documento} 30 #{zona}")
    id_persona = capturar(msg, ~r/identificador (\S+)/)
    ok!(andres_sesion, "update_person #{id_persona} localizada")

    {msg, _} = ok!(voluntario, "register_entry #{albergue} #{documento}")
    assert msg =~ "Ocupación actual: 1"

    # El voluntario consulta el albergue (permiso nuevo)
    {msg, _} = ok!(voluntario, "check_shelter #{albergue}")
    assert msg =~ "Ocupación: 1 / 150"

    # --- Un familiar deja un mensaje para Andrés (por su documento), que lo recibe ---
    {_, familiar_sesion} = ok!(nil, "connect #{familiar} 1234 ciudadano #{zona}")

    ok!(
      familiar_sesion,
      ~s(send_family_message #{documento} "Te estamos buscando, avisa cuando puedas")
    )

    {msg, _} = ok!(andres_sesion, "list_family_messages #{documento}")
    assert msg =~ "Te estamos buscando"
    assert msg =~ "(nuevo)"

    # --- Mascotas: una perdida (ciudadano) y una encontrada (voluntario) en la misma zona ---
    {msg, _} =
      ok!(familiar_sesion, "report_pet perdida perro negra mediano #{zona} 3001112233 Luna")

    id_perdida = capturar(msg, ~r/Reporte (\S+) registrado/)

    {msg, _} = ok!(voluntario, "report_pet encontrada perro negra mediano #{zona} 3004445566")
    id_encontrada = capturar(msg, ~r/Reporte (\S+) registrado/)

    # --- El sistema calcula posibles coincidencias ---
    {msg, _} = ok!(voluntario, "match_pets")
    assert msg =~ "Posibles coincidencias"
    assert msg =~ id_perdida
    assert msg =~ id_encontrada

    # --- Laura consulta el resumen global ---
    {resumen, _} = ok!(laura, "summary")
    assert resumen =~ "RESUMEN GLOBAL"
    assert resumen =~ "Albergues más ocupados"
    assert resumen =~ "Agua (#{recurso}): #{restante} litros en #{albergue}"
    assert resumen =~ "pendientes"
    assert resumen =~ "Personas localizadas"
    assert resumen =~ "(doc. #{documento}"
    assert resumen =~ "Mensajes:"
    assert resumen =~ "Mascotas:"

    # --- zone_status muestra lo asociado a la zona ---
    {estado, _} = ok!(laura, "zone_status #{zona}")
    assert estado =~ "Afectados (acumulado): 140"
    assert estado =~ "#{albergue} Albergue Norte: 1/150 ocupados"
    assert estado =~ "[n1#{s}] 30 de agua"
    assert estado =~ "[n2#{s}] 25 de agua"
    assert estado =~ "Agua (#{recurso})"
    assert estado =~ "#{id_persona} Andres (localizada)"
    assert estado =~ id_perdida
    assert estado =~ id_encontrada

    # --- Permisos: el resumen global no es para ciudadanos ni voluntarios ---
    assert {:error, msg} = Comandos.ejecutar(familiar_sesion, "summary")
    assert msg =~ "permiso"
    assert {:error, msg} = Comandos.ejecutar(voluntario, "summary")
    assert msg =~ "permiso"

    for usuario <- [laura, voluntario, familiar, andres_sesion] do
      assert {:ok, _, nil} = Comandos.ejecutar(usuario, "disconnect")
    end
  end

  test "los errores de otros módulos llegan traducidos, sin átomos crudos" do
    s = Base.encode16(:crypto.strong_rand_bytes(3))
    ciudadano = "ciud" <> s

    {_, ciudadano} = ok!(nil, "connect #{ciudadano} 1234 ciudadano centro")

    # Comando de recursos sin permiso: antes mostraba "Error de autorización: :no_autorizado"
    assert {:error, msg} = Comandos.ejecutar(ciudadano, "register_shelter a#{s} Nombre centro 10")
    assert msg == "No tienes permiso para ejecutar este comando."

    # Comando de comunidad sobre una zona inexistente
    assert {:error, msg} =
             Comandos.ejecutar(
               ciudadano,
               "report_pet perdida perro negra mediano zona_no_existe#{s} 300"
             )

    assert msg == "La zona no existe."

    assert {:ok, _, nil} = Comandos.ejecutar(ciudadano, "disconnect")
  end

  test "help se puede consultar con o sin sesión" do
    assert {:ok, texto, nil} = Comandos.ejecutar(nil, "help")
    assert texto =~ "summary"
    assert texto =~ "connect"
  end
end
