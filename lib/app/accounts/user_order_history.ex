defmodule App.Accounts.UserOrderHistory do
  @moduledoc """
  Schema para armazenar o histórico de pedidos acessados por usuários.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_order_history" do
    field :order_id, :string
    field :last_accessed_at, :utc_datetime
    field :access_count, :integer, default: 1
    belongs_to :user, App.Accounts.User

    timestamps()
  end

  @doc """
  Cria um changeset para UserOrderHistory.
  """
  def changeset(user_order_history, attrs) do
    user_order_history
    |> cast(attrs, [:user_id, :order_id, :last_accessed_at, :access_count])
    |> validate_required([:user_id, :order_id, :last_accessed_at])
    |> unique_constraint([:user_id, :order_id], name: :user_order_history_user_id_order_id_index)
  end
end
