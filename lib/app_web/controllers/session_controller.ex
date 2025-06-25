defmodule AppWeb.SessionController do
  use AppWeb, :controller

  alias App.Accounts
  alias AppWeb.Auth.Guardian

  def new(conn, _params) do
    changeset = Accounts.User.changeset(%Accounts.User{}, %{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"user" => %{"username" => username, "password" => password}}) do
    case Accounts.authenticate_user(username, password) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Bem-vindo de volta!")
        |> Guardian.Plug.sign_in(user)
        |> redirect(to: "/hello")

      {:error, :unauthorized} ->
        changeset = Accounts.User.changeset(%Accounts.User{}, %{})

        conn
        |> put_flash(:error, "Usuário ou senha inválidos.")
        |> render("new.html", changeset: changeset)
    end
  end

  def delete(conn, _params) do
    conn
    |> Guardian.Plug.sign_out()
    |> put_flash(:info, "Você saiu com sucesso.")
    |> redirect(to: "/")
  end
end
