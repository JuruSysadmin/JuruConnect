defmodule App.Accounts.Behaviour do
  @moduledoc """
  Contrato (Behaviour) para o módulo Accounts.

  Define as funções obrigatórias que devem ser implementadas
  para gerenciar contas de usuários no sistema.
  """

  @doc """
  Busca um usuário pelo ID.

  ## Parâmetros
    - `id`: ID do usuário (UUID)

  ## Retorna
    - `%User{}` se encontrado
    - Levanta `Ecto.NoResultsError` se não encontrado

  ## Exemplo
      iex> get_user!("550e8400-e29b-41d4-a716-446655440000")
      %User{id: "550e8400-e29b-41d4-a716-446655440000", username: "joao123", ...}
  """
  @callback get_user!(id :: String.t()) :: App.Accounts.User.t()

  @doc """
  Busca um usuário pelo username.

  ## Parâmetros
    - `username`: Nome de usuário (string)

  ## Retorna
    - `%User{}` se encontrado
    - `nil` se não encontrado

  ## Exemplo
      iex> get_user_by_username("joao123")
      %User{username: "joao123", name: "João Silva", ...}

      iex> get_user_by_username("usuario_inexistente")
      nil
  """
  @callback get_user_by_username(username :: String.t()) :: App.Accounts.User.t() | nil

  @doc """
  Autentica um usuário pelo username e senha.

  ## Parâmetros
    - `username`: Nome de usuário (string)
    - `password`: Senha em texto plano (string)
    - `deps`: Dependências opcionais para injeção de dependência

  ## Retorna
    - `{:ok, user}` se autenticação for bem-sucedida
    - `{:error, :invalid_credentials}` se autenticação falhar

  ## Exemplo
      iex> authenticate_user("joao123", "senha123")
      {:ok, %User{username: "joao123", ...}}

      iex> authenticate_user("joao123", "senha_errada")
      {:error, :invalid_credentials}

      iex> authenticate_user("usuario_inexistente", "senha123")
      {:error, :invalid_credentials}
  """
  @callback authenticate_user(
              username :: String.t(),
              password :: String.t(),
              deps :: map() | nil
            ) :: {:ok, App.Accounts.User.t()} | {:error, :invalid_credentials}

  @doc """
  Cria um novo usuário.

  ## Parâmetros
    - `attrs`: Atributos do usuário (map)

  ## Retorna
    - `{:ok, user}` se criação for bem-sucedida
    - `{:error, changeset}` se houver erros de validação

  ## Exemplo
      iex> create_user(%{
        username: "maria456",
        name: "Maria Santos",
        role: "manager",
        password: "senha123",
        store_id: "550e8400-e29b-41d4-a716-446655440000"
      })
      {:ok, %User{username: "maria456", ...}}
  """
  @callback create_user(attrs :: map()) ::
              {:ok, App.Accounts.User.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Atualiza um usuário existente.

  ## Parâmetros
    - `user`: Usuário a ser atualizado (%User{})
    - `attrs`: Novos atributos (map)

  ## Retorna
    - `{:ok, user}` se atualização for bem-sucedida
    - `{:error, changeset}` se houver erros de validação

  ## Exemplo
      iex> update_user(user, %{name: "João Silva Atualizado"})
      {:ok, %User{name: "João Silva Atualizado", ...}}
  """
  @callback update_user(
              user :: App.Accounts.User.t(),
              attrs :: map()
            ) :: {:ok, App.Accounts.User.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Deleta um usuário.

  ## Parâmetros
    - `user`: Usuário a ser deletado (%User{})

  ## Retorna
    - `{:ok, user}` se deleção for bem-sucedida
    - `{:error, changeset}` se houver erros

  ## Exemplo
      iex> delete_user(user)
      {:ok, %User{...}}
  """
  @callback delete_user(user :: App.Accounts.User.t()) ::
              {:ok, App.Accounts.User.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Lista todos os usuários.

  ## Parâmetros
    - `opts`: Opções opcionais (keyword list)

  ## Retorna
    - Lista de usuários

  ## Exemplo
      iex> list_users()
      [%User{...}, %User{...}]

      iex> list_users(limit: 10, offset: 0)
      [%User{...}, ...]
  """
  @callback list_users(opts :: keyword() | nil) :: [App.Accounts.User.t()]

  @doc """
  Busca usuários por loja.

  ## Parâmetros
    - `store_id`: ID da loja (UUID)

  ## Retorna
    - Lista de usuários da loja

  ## Exemplo
      iex> get_users_by_store("550e8400-e29b-41d4-a716-446655440000")
      [%User{store_id: "550e8400-e29b-41d4-a716-446655440000", ...}]
  """
  @callback get_users_by_store(store_id :: String.t()) :: [App.Accounts.User.t()]

  @doc """
  Busca usuários por função (role).

  ## Parâmetros
    - `role`: Função do usuário ("admin", "manager", "clerk")

  ## Retorna
    - Lista de usuários com a função especificada

  ## Exemplo
      iex> get_users_by_role("admin")
      [%User{role: "admin", ...}]
  """
  @callback get_users_by_role(role :: String.t()) :: [App.Accounts.User.t()]
end
