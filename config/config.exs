import Config

config :emergencias, directorio_datos: "datos"

import_config "#{config_env()}.exs"
