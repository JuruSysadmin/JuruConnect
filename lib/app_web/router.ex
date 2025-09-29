defmodule AppWeb.Router do
  use AppWeb, :router

  # CSP mais permissivo para iframes
  @csp "default-src 'self'; script-src 'self' http://127.0.0.1:4007; connect-src 'self' ws://127.0.0.1:4007; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; frame-ancestors *;"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{
      "content-security-policy" => @csp,
      "x-frame-options" => "ALLOWALL"
    }
  end

  pipeline :iframe do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AppWeb.Layouts, :iframe}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{
      "content-security-policy" => "frame-ancestors *;",
      "x-frame-options" => "ALLOWALL"
    }
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug AppWeb.Auth.Plugs.AuthenticateUser
  end

  scope "/", AppWeb do
    pipe_through :browser

    live "/", TreatySearchLive
    live "/login", UserSessionLive.Index, :new
    get "/auth/set-token", PageController, :set_token
    get "/auth/set-token-and-redirect", PageController, :set_token_and_redirect
  end

  scope "/", AppWeb do
    pipe_through [:iframe, :auth]

    live "/chat/:treaty_id", ChatLive
  end

  # Rota específica para iframes com autenticação
  scope "/iframe", AppWeb do
    pipe_through [:iframe, :auth]

    live "/chat/:treaty_id", ChatLive
  end

  # API routes
  scope "/api", AppWeb do
    pipe_through [:api, :auth]

    get "/notifications/unread-count", NotificationController, :unread_count
    get "/notifications", NotificationController, :index
    post "/notifications/:id/mark-as-read", NotificationController, :mark_as_read
    post "/notifications/mark-all-as-read", NotificationController, :mark_all_as_read
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:app, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
