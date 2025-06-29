defmodule AppWeb.SessionController do
  use AppWeb, :controller

  alias App.Accounts
  alias AppWeb.Auth.Guardian

  def new(conn, _params) do
    changeset = Accounts.User.changeset(%Accounts.User{}, %{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"user" => %{"username" => username, "password" => password}}) do
    ip_address = get_client_ip(conn)

    auth_params = %{
      username: username,
      password: password,
      ip_address: ip_address
    }

    case App.Auth.Manager.authenticate(auth_params) do
      {:ok, %{user: user, access_token: token}} ->
        conn
        |> put_flash(:info, "Bem-vindo de volta!")
        |> AppWeb.Auth.GuardianPlug.sign_in(user)
        |> put_session(:access_token, token)
        |> redirect(to: "/dashboard")

      {:error, {:rate_limited, retry_after}} ->
        changeset = Accounts.User.changeset(%Accounts.User{}, %{})
        conn
        |> put_flash(:error, "Muitas tentativas de login. Tente novamente em #{retry_after} segundos.")
        |> render("new.html", changeset: changeset)

      {:error, :invalid_credentials} ->
        App.Auth.RateLimiter.record_failed_attempt(username, ip_address)
        changeset = Accounts.User.changeset(%Accounts.User{}, %{})
        conn
        |> put_flash(:error, "Usuário ou senha inválidos.")
        |> render("new.html", changeset: changeset)

      {:error, _reason} ->
        changeset = Accounts.User.changeset(%Accounts.User{}, %{})
        conn
        |> put_flash(:error, "Erro interno. Tente novamente.")
        |> render("new.html", changeset: changeset)
    end
  end

  def callback(conn, %{"token" => token, "user_id" => user_id}) do
    # Estabelecer sessão Guardian a partir do token do Auth.Manager
    require Logger
    Logger.info("SessionController.callback - Token recebido: #{String.slice(token, 0, 20)}...")

    case App.Auth.Manager.validate_session(token) do
      {:ok, user} ->
        Logger.info("SessionController.callback - Token válido para usuário: #{user.username}")
        conn
        |> AppWeb.Auth.GuardianPlug.sign_in(user)
        |> put_session(:access_token, token)
        |> put_flash(:info, "Login realizado com sucesso!")
        |> redirect(to: "/dashboard")

      {:error, reason} ->
        Logger.error("SessionController.callback - Token inválido: #{inspect(reason)}")
        conn
        |> put_flash(:error, "Sessão inválida. Faça login novamente.")
        |> redirect(to: "/auth/login")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Parâmetros inválidos.")
    |> redirect(to: "/auth/login")
  end

  def delete(conn, _params) do
    ip_address = get_client_ip(conn)

    case get_session(conn, :access_token) do
      nil ->
        conn
        |> AppWeb.Auth.GuardianPlug.sign_out()
        |> put_flash(:info, "Você saiu com sucesso.")
        |> redirect(to: "/auth/login")

      token ->
        App.Auth.Manager.logout(token, ip_address)
        conn
        |> AppWeb.Auth.GuardianPlug.sign_out()
        |> put_flash(:info, "Você saiu com sucesso.")
        |> redirect(to: "/auth/login")
    end
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] ->
        case get_req_header(conn, "x-real-ip") do
          [ip | _] -> ip
          [] -> to_string(:inet_parse.ntoa(conn.remote_ip))
        end
    end
  end
end
