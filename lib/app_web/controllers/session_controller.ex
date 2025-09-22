defmodule AppWeb.SessionController do
  use AppWeb, :controller

  alias App.Accounts
  alias AppWeb.Auth.Guardian

  def new(conn, _params) do
    changeset = create_empty_changeset()
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"user" => %{"username" => username, "password" => password}})
      when is_binary(username) and is_binary(password) and byte_size(username) > 0 and byte_size(password) > 0 do
    case Accounts.authenticate_user(username, password) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Bem-vindo de volta!")
        |> Guardian.Plug.sign_in(user)
        |> redirect(to: "/hello")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Usuário ou senha inválidos.")
        |> render_login_form()

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Erro interno. Tente novamente.")
        |> render_login_form()
    end
  end

  def delete(conn, _params) do
    conn
    |> Guardian.Plug.sign_out()
    |> put_flash(:info, "Você saiu com sucesso.")
    |> redirect(to: "/")
  end

  # --- Private Functions ---

  defp create_empty_changeset do
    Accounts.User.changeset(%Accounts.User{}, %{})
  end

  defp render_login_form(conn) do
    changeset = create_empty_changeset()
    render(conn, "new.html", changeset: changeset)
  end
end
