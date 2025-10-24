defmodule AppWeb.Endpoint do
  @moduledoc """
  Endpoint principal da aplicação Phoenix.

  Responsável por:
  - Configurar e expor os sockets (WebSocket/LiveView)
  - Gerenciar plugs de sessão, parsers, CORS e segurança
  - Servir arquivos estáticos
  - Ser o ponto de entrada HTTP/HTTPS para todas as requisições do sistema

  Este módulo centraliza a configuração de rede e middleware da aplicação JuruConnect.
  """
  use Phoenix.Endpoint, otp_app: :app

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_app_key",
    signing_salt: "tdnofqF8",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :app,
    gzip: false,
    only: AppWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  # Configuração CORS para permitir imagens do MinIO
  plug CORSPlug, origin: ["http://localhost:9000", "http://10.1.1.23:9000"]

  plug AppWeb.Router
end
