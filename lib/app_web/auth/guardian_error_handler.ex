defmodule AppWeb.Auth.GuardianErrorHandler do
  @moduledoc """
  Guardian error handler for managing authentication errors.

  Handles various authentication error scenarios gracefully,
  providing appropriate responses for different contexts.
  """

  import Plug.Conn
  require Logger

  @behaviour Guardian.Plug.ErrorHandler

    @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, reason}, _opts) do
    Logger.debug("Guardian auth error: #{inspect(type)} - #{inspect(reason)} for path: #{conn.request_path}")

    # Limpar dados de autenticação inválidos
    conn = clear_invalid_session_data(conn, type)

    # CRÍTICO: SEMPRE enviar uma resposta para evitar NotSentError
    # Para rotas públicas, apenas continuar sem halt
    if public_route?(conn.request_path) do
      Logger.debug("Public route - continuing without halt")
      conn
    else
      # Para rotas protegidas, redirecionar para login
      Logger.debug("Protected route - redirecting to login")
      conn
      |> put_resp_header("location", "/auth/login")
      |> send_resp(302, "Redirecting to login")
      |> halt()
    end
  end

  defp clear_invalid_session_data(conn, error_type) when error_type in [:invalid_token, :token_not_found] do
    # Limpar tokens inválidos da sessão
    conn
    |> delete_session("guardian_default_token")
    |> delete_session("_csrf_token")
    |> assign(:current_user, nil)
  end

  defp clear_invalid_session_data(conn, _error_type) do
    # Para outros tipos de erro, apenas continuar
    conn
    |> assign(:current_user, nil)
  end

  defp public_route?(path) do
    public_paths = [
      "/",
      "/auth/login",
      "/login",
      "/reset-password",
      "/sessions/new",
      "/sessions/create",
      "/sessions/callback",
      "/logout"
    ]

    path in public_paths or String.starts_with?(path, "/sessions")
  end
end
