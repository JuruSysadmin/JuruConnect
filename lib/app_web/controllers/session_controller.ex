defmodule AppWeb.SessionController do
  @moduledoc """
  Controller for user session management.

  Handles user authentication, login, and logout operations.
  Provides secure session management with Guardian authentication.
  """

  use AppWeb, :controller

  alias App.Accounts
  alias AppWeb.Auth.Guardian

  @doc """
  Renders the login form.

  Displays the login page with an empty user changeset for form validation.
  """
  def new(conn, _params) do
    login_changeset = Accounts.User.changeset(%Accounts.User{}, %{})
    render(conn, "new.html", changeset: login_changeset)
  end

  @doc """
  Handles user login authentication.

  Validates credentials and creates a user session on success.
  Redirects to the main application or shows login errors.
  """
  def create(conn, %{"user" => %{"username" => username, "password" => password}})
      when is_binary(username) and is_binary(password) do
    case Accounts.authenticate_user(username, password) do
      {:ok, authenticated_user} ->
        handle_successful_login(conn, authenticated_user)

      {:error, :invalid_credentials} ->
        handle_failed_login(conn)
    end
  end

  # Handles successful authentication
  defp handle_successful_login(conn, authenticated_user) do
    conn
    |> put_flash(:info, "Bem-vindo de volta!")
    |> Guardian.Plug.sign_in(authenticated_user)
    |> redirect(to: "/hello")
  end

  # Handles failed authentication
  defp handle_failed_login(conn) do
    login_changeset = Accounts.User.changeset(%Accounts.User{}, %{})

    conn
    |> put_flash(:error, "Usuário ou senha inválidos.")
    |> render("new.html", changeset: login_changeset)
  end

  @doc """
  Handles user logout.

  Signs out the current user and redirects to the home page.
  """
  def delete(conn, _params) do
    conn
    |> Guardian.Plug.sign_out()
    |> put_flash(:info, "Você saiu com sucesso.")
    |> redirect(to: "/")
  end
end
