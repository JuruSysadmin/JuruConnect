defmodule AppWeb.Router do
  @moduledoc """
  Roteador principal da aplicação JuruConnect.

  Define pipelines, escopos e rotas para:
  - Páginas públicas
  - Áreas protegidas por autenticação
  - Rotas administrativas e super admin
  - Integração de LiveViews
  - Endpoints de API REST

  Centraliza toda a lógica de roteamento HTTP e LiveView do sistema.
  """
  use AppWeb, :router

  @csp "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' http://127.0.0.1:4007; connect-src 'self' ws://127.0.0.1:4007; img-src 'self' data: http://localhost:9000 http://10.1.1.23:9000;"

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

  scope "/", AppWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", AppWeb do
    pipe_through :browser

    live "/hello", DashboardLive
    live "/dashboard", DashboardLive, :dashboard
  end

  scope "/admin", AppWeb do
    pipe_through :browser

    live "/security", AdminLive.SecurityDashboard, :index
  end

  scope "/api", AppWeb do
    pipe_through :api
  end

  if Application.compile_env(:app, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      live "/oban", AppWeb.ObanMonitorLive, :index
    end
  end
end
