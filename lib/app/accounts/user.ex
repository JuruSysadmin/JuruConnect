defmodule App.Accounts.User do
  @moduledoc """
  Representação do esquema da entidade Usuário no contexto Contas.

  O esquema Usuário inclui informações básicas do usuário, como nome de usuário, nome, função
  e detalhes de autenticação. Ele usa UUID para chaves primárias e estrangeiras.

  ## Campos

  * `id` - A chave primária (UUID)
  * `username` - Identificador único do usuário
  * `name` - Nome completo do usuário
  * `role` - Função do usuário no sistema
  * `store_id` - UUID da loja associada
  * `website` - URL do site do usuário
  * `avatar_url` - URL para a imagem do avatar do usuário
  * `inserted_at` - Carimbo de data/hora da criação do registro
  * `updated_at` - Carimbo de data/hora da última atualização

  ## Conjuntos de alterações

  O módulo fornece uma função `changeset/2` que:
  * Valida Campos obrigatórios (nome de usuário, nome, função)
  * Garante que o nome de usuário tenha no mínimo 3 caracteres
  * Impõe restrição de nome de usuário exclusivo
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field(:username, :string)
    field(:name, :string)
    field(:role, :string)
    field(:store_id, Ecto.UUID)
    field(:website, :string)
    field(:avatar_url, :string)
    field(:password_hash, :string)
    field(:password, :string, virtual: true)

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :name, :role, :store_id, :website, :avatar_url, :password])
    |> validate_required([:username, :name, :role])
    |> validate_length(:username, min: 3)
    |> unique_constraint(:username)
    |> hash_password()
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    change(changeset, password_hash: Pbkdf2.hash_pwd_salt(password))
  end

  defp hash_password(changeset), do: changeset
end
