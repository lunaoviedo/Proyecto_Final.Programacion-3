defmodule Emergencias.Familiares.MensajesTest do
  use ExUnit.Case, async: true

  alias Emergencias.Familiares.Mensajes

  doctest Emergencias.Familiares.Mensajes

  @t0 ~U[2026-11-10 08:00:00Z]

  defp atributos(extra \\ %{}) do
    Map.merge(
      %{id: "ME001", remitente: "ana", destinatario: "luis", contenido: "Estoy bien"},
      extra
    )
  end

  # ME001 ana->luis, ME002 ana->luis, ME003 luis->ana, ME004 marta->luis (todos pendientes)
  defp mensajes_base do
    {:ok, m1, _} = Mensajes.enviar(%{}, atributos(), @t0)

    {:ok, m2, _} =
      Mensajes.enviar(m1, atributos(%{id: "ME002", contenido: "Sigo en la zona"}), @t0)

    {:ok, m3, _} =
      Mensajes.enviar(m2, atributos(%{id: "ME003", remitente: "luis", destinatario: "ana"}), @t0)

    {:ok, m4, _} =
      Mensajes.enviar(m3, atributos(%{id: "ME004", remitente: "marta"}), @t0)

    m4
  end

  defp ids({:ok, lista}), do: Enum.map(lista, & &1.id)

  describe "enviar/3 con datos válidos" do
    test "crea un mensaje pendiente con la fecha del envío" do
      assert {:ok, mensajes, mensaje} = Mensajes.enviar(%{}, atributos(), @t0)

      assert mensaje.id == "ME001"
      assert mensaje.fecha == @t0
      assert mensaje.remitente == "ana"
      assert mensaje.destinatario == "luis"
      assert mensaje.contenido == "Estoy bien"
      assert mensaje.estado == :pendiente
      assert mensajes["ME001"] == mensaje
    end

    test "recorta los espacios sobrantes" do
      assert {:ok, _, %{remitente: "ana", destinatario: "luis", contenido: "Hola"}} =
               Mensajes.enviar(
                 %{},
                 atributos(%{remitente: " ana ", destinatario: " luis ", contenido: "  Hola  "}),
                 @t0
               )
    end

    test "acepta un contenido de exactamente 500 caracteres" do
      contenido = String.duplicate("a", Mensajes.largo_maximo())

      assert {:ok, _, %{contenido: ^contenido}} =
               Mensajes.enviar(%{}, atributos(%{contenido: contenido}), @t0)
    end

    test "acepta un contenido de un solo carácter" do
      assert {:ok, _, %{contenido: "x"}} = Mensajes.enviar(%{}, atributos(%{contenido: "x"}), @t0)
    end

    test "usa la hora actual cuando no se indica la fecha" do
      assert {:ok, _, %{fecha: %DateTime{}}} = Mensajes.enviar(%{}, atributos())
    end
  end

  describe "enviar/3 con datos inválidos" do
    test "rechaza un identificador repetido" do
      {:ok, mensajes, _} = Mensajes.enviar(%{}, atributos(), @t0)
      assert {:error, :id_existente} = Mensajes.enviar(mensajes, atributos(), @t0)
    end

    test "rechaza campos vacíos o que no son texto" do
      assert {:error, :id_invalido} = Mensajes.enviar(%{}, atributos(%{id: ""}), @t0)

      assert {:error, :remitente_invalido} =
               Mensajes.enviar(%{}, atributos(%{remitente: " "}), @t0)

      assert {:error, :destinatario_invalido} =
               Mensajes.enviar(%{}, atributos(%{destinatario: nil}), @t0)

      assert {:error, :contenido_invalido} =
               Mensajes.enviar(%{}, atributos(%{contenido: ""}), @t0)

      assert {:error, :contenido_invalido} = Mensajes.enviar(%{}, atributos(%{contenido: 5}), @t0)
    end

    test "rechaza un contenido de 501 caracteres" do
      contenido = String.duplicate("a", Mensajes.largo_maximo() + 1)

      assert {:error, :contenido_demasiado_largo} =
               Mensajes.enviar(%{}, atributos(%{contenido: contenido}), @t0)
    end

    test "rechaza escribirse a uno mismo" do
      assert {:error, :destinatario_es_remitente} =
               Mensajes.enviar(%{}, atributos(%{destinatario: "ana"}), @t0)

      assert {:error, :destinatario_es_remitente} =
               Mensajes.enviar(%{}, atributos(%{destinatario: " ana "}), @t0)
    end
  end

  describe "siguiente_id/1" do
    test "continúa la numeración" do
      assert Mensajes.siguiente_id(mensajes_base()) == "ME005"
    end

    test "evita identificadores ya ocupados" do
      assert Mensajes.siguiente_id(%{"ME002" => :cualquiera}) == "ME003"
    end
  end

  describe "obtener/2" do
    test "retorna el mensaje o un error si no existe" do
      assert {:ok, %{id: "ME001"}} = Mensajes.obtener(mensajes_base(), "ME001")
      assert {:error, :mensaje_no_encontrado} = Mensajes.obtener(mensajes_base(), "ME999")
      assert {:error, :mensaje_no_encontrado} = Mensajes.obtener(mensajes_base(), nil)
    end
  end

  describe "consultar/2" do
    test "sin filtros retorna todo ordenado por identificador" do
      assert ids(Mensajes.consultar(mensajes_base())) == ["ME001", "ME002", "ME003", "ME004"]
    end

    test "filtra por remitente, destinatario y estado" do
      assert ids(Mensajes.consultar(mensajes_base(), remitente: "ana")) == ["ME001", "ME002"]

      assert ids(Mensajes.consultar(mensajes_base(), destinatario: "luis")) ==
               ["ME001", "ME002", "ME004"]

      assert ids(Mensajes.consultar(mensajes_base(), estado: "entregado")) == []
      assert ids(Mensajes.consultar(mensajes_base(), estado: :pendiente)) |> length() == 4
    end

    test "filtra por usuario, sea remitente o destinatario" do
      assert ids(Mensajes.consultar(mensajes_base(), usuario: "ana")) ==
               ["ME001", "ME002", "ME003"]

      assert ids(Mensajes.consultar(mensajes_base(), usuario: "marta")) == ["ME004"]
    end

    test "combina varios filtros" do
      assert ids(Mensajes.consultar(mensajes_base(), usuario: "ana", destinatario: "luis")) ==
               ["ME001", "ME002"]
    end

    test "sin coincidencias o sin mensajes retorna lista vacía" do
      assert {:ok, []} = Mensajes.consultar(mensajes_base(), usuario: "nadie")
      assert {:ok, []} = Mensajes.consultar(%{})
    end

    test "rechaza filtros desconocidos o con valores inválidos" do
      assert {:error, {:filtro_invalido, :contenido}} =
               Mensajes.consultar(mensajes_base(), contenido: "hola")

      assert {:error, {:filtro_invalido, :usuario}} =
               Mensajes.consultar(mensajes_base(), usuario: " ")

      assert {:error, {:filtro_invalido, :remitente}} =
               Mensajes.consultar(mensajes_base(), remitente: 5)

      assert {:error, :estado_invalido} = Mensajes.consultar(mensajes_base(), estado: "rara")

      assert {:error, {:filtro_invalido, :suelto}} =
               Mensajes.consultar(mensajes_base(), [:suelto])
    end
  end

  describe "transicion_valida?/2" do
    test "solo permite pasar de pendiente a entregado" do
      assert Mensajes.transicion_valida?(:pendiente, :entregado)
      refute Mensajes.transicion_valida?(:entregado, :pendiente)
      refute Mensajes.transicion_valida?(:pendiente, :pendiente)
      refute Mensajes.transicion_valida?(:entregado, :entregado)
    end
  end

  describe "marcar_entregado/2" do
    test "entrega un mensaje pendiente sin afectar a los demás" do
      assert {:ok, nuevos, mensaje} = Mensajes.marcar_entregado(mensajes_base(), "ME001")

      assert mensaje.estado == :entregado
      assert nuevos["ME001"] == mensaje
      assert nuevos["ME002"].estado == :pendiente
    end

    test "no permite entregar dos veces el mismo mensaje" do
      {:ok, mensajes, _} = Mensajes.marcar_entregado(mensajes_base(), "ME001")
      assert {:error, :mensaje_entregado} = Mensajes.marcar_entregado(mensajes, "ME001")
    end

    test "rechaza un mensaje inexistente" do
      assert {:error, :mensaje_no_encontrado} =
               Mensajes.marcar_entregado(mensajes_base(), "ME999")
    end
  end

  describe "entregar_pendientes/2" do
    test "entrega todos los pendientes del destinatario y solo esos" do
      assert {:ok, nuevos, entregados} = Mensajes.entregar_pendientes(mensajes_base(), "luis")

      assert Enum.map(entregados, & &1.id) == ["ME001", "ME002", "ME004"]
      assert Enum.all?(entregados, &(&1.estado == :entregado))
      assert nuevos["ME003"].estado == :pendiente
      assert nuevos["ME001"].estado == :entregado
    end

    test "no vuelve a entregar los que ya estaban entregados" do
      {:ok, mensajes, _} = Mensajes.entregar_pendientes(mensajes_base(), "luis")

      assert {:ok, ^mensajes, []} = Mensajes.entregar_pendientes(mensajes, "luis")
    end

    test "retorna lista vacía si el destinatario no tiene mensajes" do
      mensajes = mensajes_base()
      assert {:ok, ^mensajes, []} = Mensajes.entregar_pendientes(mensajes, "nadie")
      assert {:ok, %{}, []} = Mensajes.entregar_pendientes(%{}, "luis")
    end

    test "rechaza un destinatario inválido" do
      assert {:error, :destinatario_invalido} = Mensajes.entregar_pendientes(mensajes_base(), "")
      assert {:error, :destinatario_invalido} = Mensajes.entregar_pendientes(mensajes_base(), nil)
    end
  end

  describe "a_registro/1 y de_registro/1" do
    test "recuperan el mismo mensaje tras pasar por JSON" do
      {:ok, mensajes, _} = Mensajes.marcar_entregado(mensajes_base(), "ME001")
      original = mensajes["ME001"]

      {:ok, leido} = original |> Mensajes.a_registro() |> JSON.encode!() |> JSON.decode()

      assert {:ok, ^original} = Mensajes.de_registro(leido)
    end

    test "acepta un registro sin estado y lo deja pendiente" do
      registro = mensajes_base()["ME001"] |> Mensajes.a_registro() |> Map.delete("estado")

      assert {:ok, %{estado: :pendiente}} = Mensajes.de_registro(registro)
    end

    test "rechaza registros incompletos o que no son un mapa" do
      assert {:error, :registro_invalido} = Mensajes.de_registro(%{"id" => "ME001"})
      assert {:error, :registro_invalido} = Mensajes.de_registro("texto")
    end

    test "rechaza valores inválidos" do
      registro = Mensajes.a_registro(mensajes_base()["ME001"])

      assert {:error, :registro_invalido} = Mensajes.de_registro(%{registro | "id" => 1})
      assert {:error, :fecha_invalida} = Mensajes.de_registro(%{registro | "fecha" => "ayer"})
      assert {:error, :estado_invalido} = Mensajes.de_registro(%{registro | "estado" => "rara"})
    end
  end
end
