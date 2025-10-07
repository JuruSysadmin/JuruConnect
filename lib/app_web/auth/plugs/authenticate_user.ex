defmodule AppWeb.Auth.Plugs.AuthenticateUser do
  @moduledoc """
  Plug for authenticating users.
  """

  import Plug.Conn
  import Phoenix.Controller
  alias AppWeb.Auth.Guardian

  def init(opts), do: opts

  def call(conn, _opts) do
    # Verificar token na sessão ou query params (para iframes)
    token = get_session(conn, :user_token) || conn.query_params["token"]

    case token do
      nil -> handle_no_token(conn)
      token -> handle_token_authentication(conn, token)
    end
  end

  defp handle_no_token(conn) do
    conn
    |> put_flash(:error, "Você precisa estar logado para acessar esta página.")
    |> redirect(to: "/login")
    |> halt()
  end

  defp handle_token_authentication(conn, token) do
    case Guardian.resource_from_token(token) do
      {:ok, user, _claims} -> handle_successful_authentication(conn, user, token)
      {:error, _reason} -> handle_authentication_error(conn)
    end
  end

  defp handle_successful_authentication(conn, user, token) do
    conn
    |> save_token_to_session_if_needed(token)
    |> save_user_to_session(user)
    |> assign(:current_user, user)
  end

  defp handle_authentication_error(conn) do
    conn
    |> put_flash(:error, "Sessão expirada. Faça login novamente.")
    |> redirect(to: "/login")
    |> halt()
  end

  defp save_token_to_session_if_needed(conn, token) do
    if conn.query_params["token"] do
      put_session(conn, :user_token, token)
    else
      conn
    end
  end

  defp save_user_to_session(conn, user) do
    put_session(conn, :current_user, %{
      "id" => user.id,
      "name" => user.name,
      "username" => user.username,
      "role" => user.role,
      "store_id" => user.store_id
    })
  end
end
