defmodule AppWeb.Router do
  use AppWeb, :router

  @csp "default-src 'self'; script-src 'self' http://127.0.0.1:4007; connect-src 'self' ws://127.0.0.1:4007;"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @csp}
    plug AppWeb.Auth.GuardianSessionPlug
    plug Guardian.Plug.VerifySession,
         module: AppWeb.Auth.Guardian,
         error_handler: AppWeb.Auth.GuardianErrorHandler
    plug Guardian.Plug.LoadResource,
         module: AppWeb.Auth.Guardian,
         allow_blank: true
    plug AppWeb.Auth.GuardianPlug, :load_current_user
  end

  pipeline :auth do
    plug AppWeb.Auth.GuardianPlug, :ensure_authenticated
  end

  pipeline :admin do
    plug AppWeb.Auth.GuardianPlug, :require_admin
  end

  pipeline :manager_or_admin do
    plug AppWeb.Auth.GuardianPlug, :require_manager_or_admin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # === ROTAS PÚBLICAS (não autenticadas) ===
  scope "/", AppWeb do
    pipe_through :browser

    # Página inicial pública
    get "/", PageController, :home

    # Rotas de autenticação
    live "/login", UserSessionLive.Index, :new
    live "/auth/login", AuthLive.Login, :new
    live "/reset-password", AuthLive.Login, :reset_password

    # Rotas de sessão (login/logout)
    resources "/sessions", SessionController, only: [:new, :create, :delete]
    get "/sessions/callback", SessionController, :callback
    get "/logout", SessionController, :delete
  end

  # === ROTAS PROTEGIDAS (usuários autenticados) ===
  scope "/", AppWeb do
    pipe_through [:browser, :auth]

    # Dashboards principais
    live "/hello", DashboardLive
    live "/dashboard", DashboardResumoLive

    # Funcionalidades do sistema
    live "/chat/:order_id", ChatLive
    live "/buscar-pedido", OrderSearchLive
  end

  # === ROTAS ADMINISTRATIVAS (apenas admin/manager) ===
  scope "/admin", AppWeb do
    pipe_through [:browser, :auth, :manager_or_admin]

    live "/security", AdminLive.SecurityDashboard, :index
  end

  # === ROTAS SUPER ADMIN (apenas admin) ===
  scope "/super-admin", AppWeb do
    pipe_through [:browser, :auth, :admin]

    # Futuras funcionalidades exclusivas de admin
    # live "/system-config", AdminLive.SystemConfig, :index
    # live "/user-management", AdminLive.UserManagement, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", AppWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:app, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

                    scope "/dev" do
      pipe_through [:browser, :auth, :admin]

      live_dashboard "/dashboard", metrics: AppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      # Monitor Oban personalizado
      live "/oban", AppWeb.ObanMonitorLive, :index
    end
  end
end
