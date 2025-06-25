defmodule App.Accounts do
  @moduledoc """
  Contexto para gerenciamento de contas de usuários.

  Implementa o comportamento App.Accounts.Behaviour para fornecer
  funcionalidades de CRUD e autenticação de usuários.
  """

  @behaviour App.Accounts.Behaviour

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Accounts.User

  @doc """
  Busca um usuário pelo ID.

  ## Parâmetros
    - `id`: ID do usuário (UUID)

  ## Retorna
    - `%User{}` se encontrado
    - Levanta `Ecto.QueryError` se não encontrado
  """
  @impl true
  def get_user!(id) do
    Repo.get!(User, id)
  end

  @doc """
  Busca um usuário pelo username.

  ## Parâmetros
    - `username`: Nome de usuário (string)

  ## Retorna
    - `%User{}` se encontrado
    - `nil` se não encontrado
  """
  @impl true
  def get_user_by_username(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Autentica um usuário pelo username e senha.

  ## Parâmetros
    - `username`: Nome de usuário (string)
    - `password`: Senha em texto plano (string)
    - `deps`: Dependências opcionais para injeção de dependência

  ## Retorna
    - `{:ok, user}` se autenticação for bem-sucedida
    - `{:error, :unauthorized}` se autenticação falhar
  """
  @impl true
  def authenticate_user(username, password, deps \\ %{
    get_user: &get_user_by_username/1,
    verify: &Pbkdf2.verify_pass/2
  }) do
    with user when not is_nil(user) <- deps.get_user.(username),
         true <- deps.verify.(password, user.password_hash) do
      {:ok, user}
    else
      _ -> {:error, :unauthorized}
    end
  end

  @doc """
  Cria um novo usuário.

  ## Parâmetros
    - `attrs`: Atributos do usuário (map)

  ## Retorna
    - `{:ok, user}` se criação for bem-sucedida
    - `{:error, changeset}` se houver erros de validação
  """
  @impl true
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Atualiza um usuário existente.

  ## Parâmetros
    - `user`: Usuário a ser atualizado (%User{})
    - `attrs`: Novos atributos (map)

  ## Retorna
    - `{:ok, user}` se atualização for bem-sucedida
    - `{:error, changeset}` se houver erros de validação
  """
  @impl true
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deleta um usuário.

  ## Parâmetros
    - `user`: Usuário a ser deletado (%User{})

  ## Retorna
    - `{:ok, user}` se deleção for bem-sucedida
    - `{:error, changeset}` se houver erros
  """
  @impl true
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Lista todos os usuários.

  ## Parâmetros
    - `opts`: Opções opcionais (keyword list)

  ## Retorna
    - Lista de usuários
  """
  @impl true
  def list_users(opts \\ []) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    User
    |> maybe_limit(limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Busca usuários por loja.

  ## Parâmetros
    - `store_id`: ID da loja (UUID)

  ## Retorna
    - Lista de usuários da loja
  """
  @impl true
  def get_users_by_store(store_id) do
    User
    |> where(store_id: ^store_id)
    |> Repo.all()
  end

  @doc """
  Busca usuários por função (role).

  ## Parâmetros
    - `role`: Função do usuário ("admin", "manager", "clerk")

  ## Retorna
    - Lista de usuários com a função especificada
  """
  @impl true
  def get_users_by_role(role) do
    User
    |> where(role: ^role)
    |> Repo.all()
  end

  # Funções auxiliares privadas

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)
end
