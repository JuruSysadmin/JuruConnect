defmodule App.Auth.EnsureAuthenticated do
  @moduledoc """
  Um plug para garantir que uma solicitação seja autenticada usando um token Bearer.

  Este plug verifica a presença de um cabeçalho de "autorização" com um token Bearer,
  verifica o token usando o módulo `Guardian` e atribui o usuário autenticado
  à conexão sob a chave `:current_user`.

  Se a autenticação falhar em qualquer etapa, a conexão será interrompida e um status 401 Unauthorized
  será retornado.

  ## Uso

  Adicione este plug ao seu pipeline ou controlador para proteger rotas que exigem autenticação.

  ## Funções

  * `init/1` - Inicializa opções para o plug.
  * `call/2` - Processa a conexão, autenticando o usuário, se possível.
  """

  import Plug.Conn
  alias AppWeb.Auth.Guardian

  def init(opts), do: opts

  def call(conn, opts) do
    auth = Keyword.get(opts, :auth, Guardian)

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- auth.decode_and_verify(token),
         {:ok, user} <- auth.resource_from_claims(claims) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> halt()
    end
  end
end
