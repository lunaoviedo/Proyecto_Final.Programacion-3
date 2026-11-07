defmodule Emergencias.PersistenciaTest do
  @moduledoc """
  Pruebas del módulo `Emergencias.Persistencia`.

  Cada prueba utiliza un directorio temporal propio, por lo que no modifica los
  datos reales del sistema. No se ejecutan en paralelo porque cambian la
  configuración global de la aplicación.
  """

  use ExUnit.Case, async: false

  alias Emergencias.Persistencia

  doctest Emergencias.Persistencia

  setup do
    directorio =
      Path.join(System.tmp_dir!(), "emergencias_prueba_#{System.unique_integer([:positive])}")

    anterior = Application.get_env(:emergencias, :directorio_datos)
    Application.put_env(:emergencias, :directorio_datos, directorio)

    on_exit(fn ->
      if anterior do
        Application.put_env(:emergencias, :directorio_datos, anterior)
      else
        Application.delete_env(:emergencias, :directorio_datos)
      end

      File.rm_rf(directorio)
    end)

    %{directorio: directorio}
  end

  describe "guardar/2 y cargar/1 con datos válidos" do
    test "recupera los registros en el mismo orden en que se guardaron" do
      registros = [
        %{"id" => "M001", "especie" => "perro"},
        %{"id" => "M002", "especie" => "gato"},
        %{"id" => "M003", "especie" => "loro"}
      ]

      assert :ok = Persistencia.guardar(:mascotas, registros)
      assert {:ok, ^registros} = Persistencia.cargar(:mascotas)
    end

    test "conserva tildes, comillas, punto y coma y saltos de línea" do
      registro = %{
        "id" => "P001",
        "nombre" => "Andrés Peña",
        "nota" => "Dijo: \"estoy bien\"; está en el albergue\nsegunda línea"
      }

      assert :ok = Persistencia.guardar(:personas, [registro])
      assert {:ok, [^registro]} = Persistencia.cargar(:personas)
    end

    test "soporta listas y mapas anidados" do
      registro = %{
        "id" => "P002",
        "historial" => [
          %{"estado" => "reportada", "fecha" => "2026-11-07"},
          %{"estado" => "localizada", "fecha" => "2026-11-08"}
        ]
      }

      assert :ok = Persistencia.guardar(:personas, [registro])
      assert {:ok, [^registro]} = Persistencia.cargar(:personas)
    end

    test "serializa los átomos como cadenas" do
      assert :ok = Persistencia.guardar(:mascotas, [%{"estado" => :activa}])
      assert {:ok, [%{"estado" => "activa"}]} = Persistencia.cargar(:mascotas)
    end

    test "guardar reemplaza el contenido anterior" do
      assert :ok = Persistencia.guardar(:mascotas, [%{"id" => "M001"}, %{"id" => "M002"}])
      assert :ok = Persistencia.guardar(:mascotas, [%{"id" => "M003"}])

      assert {:ok, [%{"id" => "M003"}]} = Persistencia.cargar(:mascotas)
    end

    test "no deja archivos temporales después de guardar" do
      assert :ok = Persistencia.guardar(:mascotas, [%{"id" => "M001"}])

      refute File.exists?(Persistencia.ruta_archivo(:mascotas) <> ".tmp")
    end
  end

  describe "agregar/2" do
    test "crea el archivo si no existe y acumula los registros" do
      assert :ok = Persistencia.agregar(:movimientos, %{"recurso" => "R001", "cantidad" => 30})
      assert :ok = Persistencia.agregar(:movimientos, %{"recurso" => "R001", "cantidad" => -10})

      assert {:ok, movimientos} = Persistencia.cargar(:movimientos)

      assert movimientos == [
               %{"recurso" => "R001", "cantidad" => 30},
               %{"recurso" => "R001", "cantidad" => -10}
             ]
    end

    test "agrega al final de un archivo existente sin perder lo anterior" do
      assert :ok = Persistencia.guardar(:movimientos, [%{"id" => 1}])
      assert :ok = Persistencia.agregar(:movimientos, %{"id" => 2})

      assert {:ok, [%{"id" => 1}, %{"id" => 2}]} = Persistencia.cargar(:movimientos)
    end
  end

  describe "casos límite" do
    test "cargar una entidad sin archivo retorna una lista vacía" do
      assert {:ok, []} = Persistencia.cargar(:entidad_inexistente)
    end

    test "guardar una lista vacía deja un archivo que se carga como lista vacía" do
      assert :ok = Persistencia.guardar(:mascotas, [])
      assert {:ok, []} = Persistencia.cargar(:mascotas)
    end

    test "las líneas en blanco del archivo se ignoran" do
      ruta = Persistencia.ruta_archivo(:mascotas)
      File.mkdir_p!(Path.dirname(ruta))
      File.write!(ruta, "{\"id\":\"M001\"}\n\n   \n{\"id\":\"M002\"}\n")

      assert {:ok, [%{"id" => "M001"}, %{"id" => "M002"}]} = Persistencia.cargar(:mascotas)
    end

    test "guarda correctamente un registro vacío" do
      assert :ok = Persistencia.guardar(:mascotas, [%{}])
      assert {:ok, [%{}]} = Persistencia.cargar(:mascotas)
    end
  end

  describe "datos inválidos" do
    test "cargar informa la línea física cuando el contenido no es JSON válido" do
      ruta = Persistencia.ruta_archivo(:mascotas)
      File.mkdir_p!(Path.dirname(ruta))
      File.write!(ruta, "{\"id\":\"M001\"}\n{esto no es json\n")

      assert {:error, {:linea_invalida, 2}} = Persistencia.cargar(:mascotas)
    end

    test "cargar rechaza líneas que son JSON válido pero no un objeto" do
      ruta = Persistencia.ruta_archivo(:mascotas)
      File.mkdir_p!(Path.dirname(ruta))
      File.write!(ruta, "[1, 2, 3]\n")

      assert {:error, {:linea_invalida, 1}} = Persistencia.cargar(:mascotas)
    end

    test "guardar rechaza elementos que no son mapas" do
      assert {:error, {:registro_invalido, "texto"}} =
               Persistencia.guardar(:mascotas, [%{"id" => "M001"}, "texto"])
    end

    test "guardar rechaza valores que no se pueden representar como JSON" do
      assert {:error, {:no_codificable, _detalle}} =
               Persistencia.guardar(:mascotas, [%{"id" => {1, 2}}])
    end

    test "agregar rechaza valores que no se pueden representar como JSON" do
      assert {:error, {:no_codificable, _detalle}} =
               Persistencia.agregar(:movimientos, %{"id" => {1, 2}})
    end

    test "un guardado fallido no altera el archivo anterior ni deja temporales" do
      assert :ok = Persistencia.guardar(:mascotas, [%{"id" => "M001"}])

      assert {:error, _motivo} = Persistencia.guardar(:mascotas, [%{"id" => "M002"}, "texto"])

      assert {:ok, [%{"id" => "M001"}]} = Persistencia.cargar(:mascotas)
      refute File.exists?(Persistencia.ruta_archivo(:mascotas) <> ".tmp")
    end
  end
end
