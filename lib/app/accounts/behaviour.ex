defmodule App.Accounts.Behaviour do
  @moduledoc """
  Contrato (Behaviour) para o módulo Accounts.

  Define as funções obrigatórias que devem ser implementadas
  para gerenciar contas de usuários no sistema.
  """

  @callback get_user!(id :: String.t()) :: {:ok, App.Accounts.User.t()} | {:error, :not_found}

  @callback get_user_by_username(username :: String.t()) :: App.Accounts.User.t() | nil

  @callback authenticate_user(
              username :: String.t(),
              password :: String.t(),
              deps :: map() | nil
            ) :: {:ok, App.Accounts.User.t()} | {:error, :unauthorized}

  @callback create_user(attrs :: map()) ::
              {:ok, App.Accounts.User.t()} | {:error, Ecto.Changeset.t()}

  @callback update_user(
              user :: App.Accounts.User.t(),
              attrs :: map()
            ) :: {:ok, App.Accounts.User.t()} | {:error, Ecto.Changeset.t()}

  @callback delete_user(user :: App.Accounts.User.t()) ::
              {:ok, App.Accounts.User.t()} | {:error, Ecto.Changeset.t()}

  @callback list_users(opts :: keyword() | nil) :: [App.Accounts.User.t()]

  @callback get_users_by_store(store_id :: String.t()) :: [App.Accounts.User.t()]

  @callback get_users_by_role(role :: String.t()) :: [App.Accounts.User.t()]
end
