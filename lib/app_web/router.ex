defmodule AppWeb.Router do
  use AppWeb, :router

  @csp "default-src 'self'; script-src 'self' http://127.0.0.1:4007; connect-src 'self' ws://127.0.0.1:4007; img-src 'self' data: http://localhost:9000 http://10.1.1.23:9000;"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @csp}
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # === ROTAS PÚBLICAS (não autenticadas) ===
  scope "/", AppWeb do
    pipe_through :browser

    # Página inicial pública
    get "/", PageController, :home

    # Rotas de autenticação removidas
  end

  # === ROTAS PROTEGIDAS (usuários autenticados) ===
  scope "/", AppWeb do
    pipe_through :browser

    # Dashboards principais
    live "/hello", DashboardLive
    live "/dashboard", DashboardResumoLive

    # Funcionalidades do sistema (mantém protegidas se necessário)
    live "/chat/:order_id", ChatLive
    live "/buscar-pedido", OrderSearchLive
  end

  # === ROTAS ADMINISTRATIVAS (apenas admin/manager) ===
  scope "/admin", AppWeb do
    pipe_through :browser

    live_session :admin,
      on_mount: [{AppWeb.LiveUserAuth, :require_authenticated_user}] do
      live "/security", AdminLive.SecurityDashboard, :index
      live "/health", HealthLive.Dashboard, :index
    end
  end

  # === ROTAS SUPER ADMIN (apenas admin) ===
  scope "/super-admin", AppWeb do
    pipe_through :browser

    # Futuras funcionalidades exclusivas de admin
    # live "/system-config", AdminLive.SystemConfig, :index
    # live "/user-management", AdminLive.UserManagement, :index
  end

  # === ROTAS DE API ===
  scope "/api", AppWeb do
    pipe_through :api

    # Health Check endpoints
    get "/health", HealthController, :index
    get "/health/detailed", HealthController, :detailed
    get "/health/api-status", HealthController, :api_status
    post "/health/check", HealthController, :trigger_check
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:app, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      # Monitor Oban personalizado
      live "/oban", AppWeb.ObanMonitorLive, :index
    end
  end
end
