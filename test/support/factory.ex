defmodule App.Factory do
  @moduledoc """
  Factory para criação de dados de teste
  """

  def build(:user, attrs) do
    attrs = Enum.into(attrs, %{})

    %{
      id: UUID.uuid4(),
      username: Map.get(attrs, :username, "user#{System.unique_integer([:positive])}"),
      name: Map.get(attrs, :name, "Test User"),
      role: Map.get(attrs, :role, "user"),
      store_id: Map.get(attrs, :store_id, UUID.uuid4()),
      password_hash: Map.get(attrs, :password_hash, Pbkdf2.hash_pwd_salt("password123"))
    }
  end

  def build(factory_name, attrs) do
    raise ArgumentError, "Unknown factory: #{factory_name}"
  end
end
