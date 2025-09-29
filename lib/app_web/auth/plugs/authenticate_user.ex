defmodule AppWeb.Auth.Plugs.AuthenticateUser do
  import Plug.Conn
  import Phoenix.Controller
  alias AppWeb.Auth.Guardian

  def init(opts), do: opts

  def call(conn, _opts) do
    # Verificar token na sessão ou query params (para iframes)
    token = get_session(conn, :user_token) || conn.query_params["token"]

    case token do
      nil ->
        conn
        |> put_flash(:error, "Você precisa estar logado para acessar esta página.")
        |> redirect(to: "/login")
        |> halt()

      token ->
        case Guardian.resource_from_token(token) do
          {:ok, user, _claims} ->
            # Se o token veio da query string, salvar na sessão para futuras requisições
            conn = if conn.query_params["token"] do
              put_session(conn, :user_token, token)
            else
              conn
            end
            assign(conn, :current_user, user)

          {:error, _reason} ->
            conn
            |> put_flash(:error, "Sessão expirada. Faça login novamente.")
            |> redirect(to: "/login")
            |> halt()
        end
    end
  end
end
