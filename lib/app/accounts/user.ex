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
  * `password` - Campo virtual para entrada de senha
  * `password_hash` - Senha criptografada armazenada no banco de dados
  * `website` - URL do site do usuário
  * `avatar_url` - URL para a imagem do avatar do usuário
  * `inserted_at` - Carimbo de data/hora da criação do registro
  * `updated_at` - Carimbo de data/hora da última atualização

  ## Conjuntos de alterações

  O módulo fornece uma função `changeset/2` que:
  * Valida Campos obrigatórios (nome de usuário, nome, função)
  * Garante que o nome de usuário tenha no mínimo 3 caracteres
  * Impõe restrição de nome de usuário exclusivo
  * Faz hash automático de senhas antes do armazenamento
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
    field(:password, :string, virtual: true)
    field(:password_hash, :string)
    field(:website, :string)
    field(:avatar_url, :string)

    timestamps()
  end

  @doc """
  Cria um conjunto de alterações para criar um usuário.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :name, :role, :store_id, :password, :website, :avatar_url])
    |> validate_required([:username, :name, :role])
    |> validate_length(:username, min: 3)
    |> unique_constraint(:username)
    |> hash_password()
  end

  defp hash_password(changeset) do
    if changeset.valid? && get_change(changeset, :password) do
      password = get_change(changeset, :password)

      put_change(changeset, :password_hash, Pbkdf2.hash_pwd_salt(password))
    else
      changeset
    end
  end
end
