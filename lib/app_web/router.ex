defmodule AppWeb.Router do
  @moduledoc """
  Centraliza toda a lógica de roteamento HTTP e LiveView do sistema JuruConnect.
  """
  use AppWeb, :router

  # Content Security Policy para desenvolvimento local
  @content_security_policy "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' http://127.0.0.1:4007; connect-src 'self' ws://127.0.0.1:4007; img-src 'self' data:;"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @content_security_policy}
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
  end

  scope "/super-admin", AppWeb do
    pipe_through :browser
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
