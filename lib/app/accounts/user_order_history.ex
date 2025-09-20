defmodule App.Accounts.UserOrderHistory do
  @moduledoc """
  Tracks user access patterns to orders for analytics and personalization.

  This schema maintains a record of which orders users have accessed,
  enabling features like recently viewed orders and usage analytics.
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
  Creates a changeset for tracking user order access.

  Ensures each user can only have one record per order, preventing duplicates
  while allowing access count updates for analytics.
  """
  def changeset(user_order_history, attrs) do
    user_order_history
    |> cast(attrs, [:user_id, :order_id, :last_accessed_at, :access_count])
    |> validate_required([:user_id, :order_id, :last_accessed_at])
    |> unique_constraint([:user_id, :order_id], name: :user_order_history_user_id_order_id_index)
  end

  @doc """
  Creates a changeset for recording a new order access.

  Automatically sets the current timestamp and initializes access count to 1.
  """
  def record_order_access(user_id, order_id) do
    %__MODULE__{}
    |> changeset(%{
      user_id: user_id,
      order_id: order_id,
      last_accessed_at: DateTime.utc_now(),
      access_count: 1
    })
  end

  @doc """
  Creates a changeset for updating an existing order access record.

  Increments the access count and updates the timestamp to track repeated access.
  """
  def update_order_access(user_order_history) do
    user_order_history
    |> changeset(%{
      last_accessed_at: DateTime.utc_now(),
      access_count: user_order_history.access_count + 1
    })
  end
end
