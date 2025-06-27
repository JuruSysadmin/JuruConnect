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
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AppWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/hello", DashboardLive
    live "/dashboard", DashboardResumoLive
    live "/login", UserSessionLive.Index, :new
    live "/chat/:order_id", ChatLive
    live "/buscar-pedido", OrderSearchLive
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
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
