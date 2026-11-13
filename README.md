# Emergencias

Sistema distribuido de coordinación y gestión de emergencias tras un terremoto,
escrito en Elixir. Proyecto final de Programación III (Universidad del Quindío).
Registra usuarios, zonas afectadas, necesidades, recursos, albergues, personas,
mensajes entre familiares y reportes de mascotas. Cada componente con estado es un
`GenServer` bajo un supervisor, y la información se guarda en archivos de texto plano.

## Requisitos

- Elixir 1.20 o superior (el proyecto usa el módulo `JSON` de la biblioteca estándar).
- No tiene dependencias externas.

## Cómo ejecutarlo

Desde la raíz del proyecto:

```bash
mix emergencias
```

Abre la consola interactiva. Escribe `help` para ver los comandos y `salir`
(o `Ctrl+D`) para terminar. También se puede ejecutar un archivo de comandos:

```bash
mix emergencias < comandos.txt
```

Los datos quedan en la carpeta `datos/` (un archivo `.jsonl` por entidad) y se
cargan de nuevo al volver a arrancar. Para empezar de cero, borra esa carpeta.

## Pruebas

```bash
mix test
```

Las pruebas escriben en `tmp/test_datos/`, no en `datos/` (ver `config/test.exs`).
`test/emergencias/flujo_enunciado_test.exs` recorre el flujo de ejemplo del
enunciado completo.

## Flujo de ejemplo

```text
connect laura 1234 coordinador centro
register_zone centro "Zona Centro" critico 100
register_sector centro s3 "Sector 3" 50
register_shelter a01 "Albergue Norte" centro 150
register_resource r001 Agua agua 50 litros a01
register_need n001 a01 agua 30
report_person Andres 1234567 30 centro
zone_status centro
summary
```

## Tipos de usuario y permisos

| Tipo | Puede |
| --- | --- |
| `ciudadano` | Registrar y listar necesidades, reportar y buscar personas, enviar y leer mensajes de familiares, reportar mascotas, consultar zonas |
| `voluntario` | Lo del ciudadano, más cotejar mascotas, registrar ingresos y salidas de albergues y consultar albergues |
| `coordinador` | Todo, incluido `summary` (resumen global) |
| `administrador` | Todo |

Al ejecutar `connect usuario clave tipo zona`, si el usuario no existe se registra
automáticamente; si existe, se valida la contraseña.

## Comandos de mascotas y familiares

### Mascotas

```text
report_pet tipo especie color tamano zona contacto [nombre|-] [rasgos|-]
list_pets [especie=..] [zona=..] [estado=..] [tipo=..]
match_pets
link_pets id_a id_b
confirm_match id_a id_b
discard_match id
```

- `tipo` es `perdida` o `encontrada` (también se aceptan `lost` y `found`) y `tamano` es `pequeno`, `mediano` o `grande`.
- Los rasgos se separan con comas y se escriben entre comillas si llevan espacios; `-` indica que no hay nombre o rasgos.
- `match_pets` calcula las posibles coincidencias entre reportes activos. `link_pets` las marca como posible coincidencia, `confirm_match` cierra ambos reportes y `discard_match` los devuelve a activos.
- Un reporte resuelto no puede cerrarse de nuevo.

### Familiares

```text
report_person nombre documento edad zona [estado]
find_person documento
find_person [nombre=..] [documento=..] [zona=..] [estado=..]
update_person id estado
person_history id
send_family_message documento contenido
list_family_messages documento
```

- Una persona puede registrarse en cualquier estado salvo `reunificada`, que es final; por defecto queda `reportada`. Los estados son `sin_informacion`, `reportada`, `localizada`, `trasladada`, `en_albergue` y `reunificada`.
- `person_history` muestra cada cambio de estado con su fecha.
- El destinatario de un mensaje es el documento de una persona registrada con `report_person`. Al listar los mensajes de un documento, los pendientes quedan marcados como entregados.

Ejemplo:

```text
report_person Andres 1090123456 28 centro localizada
send_family_message 1090123456 "Estoy bien, estoy en el albergue norte"
list_family_messages 1090123456
```

## Algoritmo de coincidencias de mascotas

Cada pareja formada por un reporte `perdida` y uno `encontrada`, ambos activos, recibe un puntaje de similitud. Si son de especies distintas se descarta; en caso contrario se suman:

| Atributo | Puntos |
| --- | --- |
| Color igual | 40 |
| Zona igual | 30 |
| Nombre igual (solo si ambos lo conocen) | 25 |
| Características (índice de Jaccard sobre `MapSet`) | hasta 20 |
| Tamaño igual (adyacente: 7) | 15 |

El máximo es 130 y una pareja es posible coincidencia desde 60 puntos. Se prefiere detectar de más: una coincidencia no detectada mantiene separado a un animal de su familia, mientras que una candidata incorrecta solo requiere que una persona la descarte. Por eso color y zona iguales, los atributos más fáciles de observar, bastan por sí solos para superar el umbral.

## Estructura

```text
lib/emergencias/
├── application.ex        árbol de supervisión
├── cli.ex                consola interactiva
├── comandos.ex           interpreta y despacha comandos (zonas, sesión, resumen)
├── errores.ex            mensajes de error legibles de todos los módulos
├── informes.ex           summary y detalle de zona (cruza todos los servidores)
├── persistencia.ex       lectura y escritura de archivos .jsonl
├── usuarios/             usuarios, permisos y sesiones (GenServer)
├── zonas/                zona -> sectores -> puntos (recursividad) y su GenServer
├── recursos/             inventario, albergues y necesidades (+ sus comandos)
├── familiares/           personas y mensajes entre familiares
├── mascotas/             reportes y coincidencias de mascotas
└── comunidad/            comandos de personas, mensajes y mascotas
lib/mix/tasks/emergencias.ex   tarea `mix emergencias`
```

Capas: la consola llama a `Comandos`, que valida sesión y permisos con
`ServidorSesiones` y delega en los servidores (`GenServer`); la lógica pura de cada
dominio vive en módulos sin procesos, y solo los servidores usan `Persistencia`.

## Información del proyecto

- Autores: Simón López E., Luna Sofía Oviedo Ríos, David Alejandro Henao Jaramillo
- Licencia: GNU GPL v3
