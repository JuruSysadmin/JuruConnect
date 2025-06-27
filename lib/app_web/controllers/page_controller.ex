defmodule AppWeb.PageController do
  use AppWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def hello(conn, _params) do
    text(conn, "Hello world")
  end

  # PWA Actions
  def manifest(conn, _params) do
    manifest = %{
      name: "JuruConnect Dashboard",
      short_name: "JuruConnect",
      description: "Dashboard de vendas e controle comercial",
      start_url: "/",
      display: "standalone",
      background_color: "#ffffff",
      theme_color: "#3b82f6",
      orientation: "portrait-primary",
      scope: "/",
      icons: [
        %{
          src: "/assets/icon-192x192.png",
          sizes: "192x192",
          type: "image/png",
          purpose: "maskable any"
        },
        %{
          src: "/assets/icon-512x512.png",
          sizes: "512x512",
          type: "image/png",
          purpose: "maskable any"
        },
        %{
          src: "/assets/icon-180x180.png",
          sizes: "180x180",
          type: "image/png",
          purpose: "apple-touch-icon"
        }
      ],
      categories: ["business", "productivity"]
    }

    conn
    |> put_resp_content_type("application/manifest+json")
    |> json(manifest)
  end

  def service_worker(conn, _params) do
    sw_content = File.read!(Path.join([:code.priv_dir(:app), "static", "sw.js"]))

    conn
    |> put_resp_content_type("application/javascript")
    |> text(sw_content)
  end

  def offline(conn, _params) do
    render(conn, :offline, layout: {AppWeb.Layouts, :app})
  end
end
