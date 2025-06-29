defmodule App.Factory do
  @moduledoc """
  Factory para criação de dados de teste
  """

  alias App.Accounts.User
  alias App.Repo

  def insert(factory_name, attrs \\ %{}) do
    factory_name
    |> build(attrs)
    |> Repo.insert!()
  end

  def build(:user, attrs) do
    attrs = Enum.into(attrs, %{})

    %User{
      id: Ecto.UUID.generate(),
      username: Map.get(attrs, :username, "user#{System.unique_integer([:positive])}"),
      name: Map.get(attrs, :name, "Test User"),
      role: Map.get(attrs, :role, "user"),
      store_id: Map.get(attrs, :store_id, Ecto.UUID.generate()),
      password_hash: Map.get(attrs, :password_hash, Argon2.hash_pwd_salt("password123"))
    }
  end

  def build(factory_name, attrs) do
    raise ArgumentError, "Unknown factory: #{factory_name}"
  end
end
