defmodule App.Accounts do
  @moduledoc """
  Contexto para gerenciamento de contas de usuários.

  Implementa o comportamento App.Accounts.Behaviour para fornecer
  funcionalidades de CRUD e autenticação de usuários.
  """

  @behaviour App.Accounts.Behaviour

  import Ecto.Query, warn: false
  alias App.Accounts.User
  alias App.Repo

  @impl true
  def get_user!(id) do
    Repo.get!(User, id)
  end

  @impl true
  def get_user_by_username(username) do
    Repo.get_by(User, username: username)
  end

  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def count_users do
    Repo.aggregate(User, :count, :id)
  end

  def count_active_users do
    # Assumindo que usuários ativos fizeram login nos últimos 30 dias
    thirty_days_ago = Date.add(Date.utc_today(), -30)

    from(u in User,
      where: u.last_login_at >= ^thirty_days_ago or is_nil(u.last_login_at),
      select: count(u.id)
    )
    |> Repo.one()
  end

  def count_users_by_role(role) do
    from(u in User,
      where: u.role == ^role,
      select: count(u.id)
    )
    |> Repo.one()
  end

  @impl true
  def authenticate_user(
        username,
        password,
        deps \\ %{
          get_user: &get_user_by_username/1
        }
      ) do
    with user when not is_nil(user) <- deps.get_user.(username) do
      {:ok, user}
    else
      _ -> {:error, :unauthorized}
    end
  end

  @impl true
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @impl true
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @impl true
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @impl true
  def list_users(opts \\ []) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    User
    |> maybe_limit(limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @impl true
  def get_users_by_store(store_id) do
    User
    |> where(store_id: ^store_id)
    |> Repo.all()
  end

  @impl true
  def get_users_by_role(role) do
    User
    |> where(role: ^role)
    |> Repo.all()
  end

  @doc """
  Busca usuários por uma lista de usernames.

  Usado pelo sistema de menções para encontrar usuários mencionados
  em mensagens do chat.

  ## Parâmetros
  - usernames: Lista de strings contendo os usernames a buscar

  ## Retorna
  Lista de usuários encontrados (pode ser menor que a lista original
  se alguns usernames não existirem).
  """
  def get_users_by_usernames(usernames) when is_list(usernames) do
    User
    |> where([u], u.username in ^usernames)
    |> Repo.all()
  end

  def get_users_by_usernames(_), do: []

  # Funções auxiliares privadas

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)
end
