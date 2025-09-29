defmodule App.Treaties.TreatyActivity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "treaty_activities" do
    field :activity_type, :string
    field :description, :string
    field :metadata, :map
    field :activity_at, :utc_datetime

    # Relacionamentos
    belongs_to :treaty, App.Treaties.Treaty
    belongs_to :user, App.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a treaty activity.
  """
  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:treaty_id, :user_id, :activity_type, :description, :metadata, :activity_at])
    |> validate_required([:treaty_id, :activity_type, :activity_at])
    |> validate_inclusion(:activity_type, [
      "created", "status_changed", "message_sent", "closed", "reopened",
      "tag_added", "tag_removed", "priority_changed", "rated", "commented"
    ])
    |> validate_length(:description, max: 1000)
    |> foreign_key_constraint(:treaty_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for creating a new activity.
  """
  def create_changeset(activity, attrs) do
    activity
    |> changeset(attrs)
    |> put_change(:activity_at, DateTime.utc_now())
  end
end
