defmodule AppWeb.Auth.Plugs.AuthenticateUser do
  import Plug.Conn
  import Phoenix.Controller
  require Logger
  alias AppWeb.Auth.Guardian

  def init(opts), do: opts

  def call(conn, _opts) do
    # Verificar token na sessão
    token = get_session(conn, :user_token)
    Logger.info("AuthenticateUser: Token na sessão = #{inspect(token)}")

    case token do
      nil ->
        Logger.info("AuthenticateUser: Nenhum token encontrado")
        conn
        |> put_flash(:error, "Você precisa estar logado para acessar esta página.")
        |> redirect(to: "/login")
        |> halt()

      token ->
        case Guardian.resource_from_token(token) do
          {:ok, user, _claims} ->
            Logger.info("AuthenticateUser: Usuário autenticado = #{user.name || user.username}")
            assign(conn, :current_user, user)

          {:error, reason} ->
            Logger.error("AuthenticateUser: Erro ao decodificar token = #{inspect(reason)}")
            conn
            |> put_flash(:error, "Sessão expirada. Faça login novamente.")
            |> redirect(to: "/login")
            |> halt()
        end
    end
  end
end
