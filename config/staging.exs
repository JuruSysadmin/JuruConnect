import Config

# Configuração específica para ambiente de staging
# Similar à produção mas com algumas ferramentas de debug habilitadas

config :app, AppWeb.Endpoint,
  # Desabilitar todas as funções de desenvolvimento
  code_reloader: false,
  debug_errors: false,
  live_reload: false,

  # Configurações específicas para staging
  cache_static_manifest: "priv/static/cache_manifest.json"

# Log level mais verboso para staging (debugging)
config :logger, level: :info

# Manter stacktraces para debugging em staging
config :phoenix, :stacktrace_depth, 10

# Desabilitar watchers que consomem recursos
config :app, AppWeb.Endpoint, watchers: []

# Feature flags para staging
config :app, :features,
  enable_debug_mode: true,
  enable_hot_reload_staging: System.get_env("ENABLE_HOT_RELOAD_STAGING", "false") == "true"

# Ambiente de staging pode ter algumas ferramentas de desenvolvimento controladas
if System.get_env("ENABLE_HOT_RELOAD_STAGING") == "true" do
  config :app, AppWeb.Endpoint,
    code_reloader: true,
    live_reload: [
      patterns: [
        ~r"priv/static/.*(js|css)$",
        ~r"lib/app_web/(controllers|live)/.*(ex|heex)$"
      ]
    ]
end
