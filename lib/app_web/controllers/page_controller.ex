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

  def set_token(conn, %{"token" => token}) do
    conn
    |> put_session(:user_token, token)
    |> redirect(to: "/buscar-pedido")
  end
end
