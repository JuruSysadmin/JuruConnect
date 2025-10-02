defmodule App.Treaties.TreatyReminder do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "treaty_reminders" do
    field :message, :string
    field :status, :string, default: "pending"
    field :notified_at, :utc_datetime

    # Relacionamentos
    belongs_to :treaty, App.Treaties.Treaty

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a treaty reminder.
  """
  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:treaty_id, :message, :status, :notified_at])
    |> validate_required([:treaty_id, :message])
    |> validate_length(:message, min: 1, max: 1000)
    |> validate_inclusion(:status, ["pending", "notified"])
    |> foreign_key_constraint(:treaty_id)
  end

  @doc """
  Creates a changeset for creating a new reminder.
  """
  def create_changeset(reminder, attrs) do
    reminder
    |> changeset(attrs)
    |> put_change(:status, "pending")
  end
end
