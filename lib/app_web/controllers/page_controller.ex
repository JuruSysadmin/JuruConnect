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
    |> redirect(to: "/")
  end

  def set_token_and_redirect(conn, %{"token" => token, "redirect" => redirect_path}) do
    conn
    |> put_session(:user_token, token)
    |> redirect(to: redirect_path)
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Logout realizado com sucesso!")
    |> redirect(to: "/login")
  end
end
