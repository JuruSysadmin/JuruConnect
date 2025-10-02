defmodule App.GlobalReminders.GlobalReminder do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "global_reminders" do
    field :title, :string
    field :description, :string
    field :scheduled_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :status, :string, default: "pending"
    field :notification_type, :string, default: "popup"
    field :recurring_type, :string, default: "none"
    field :priority, :string, default: "medium"

    # Relacionamento
    belongs_to :user, App.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for global reminder creation.
  """
  def create_changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:user_id, :title, :description, :scheduled_at, :notification_type, :recurring_type, :priority])
    |> validate_required([:user_id, :title, :scheduled_at])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:description, max: 1000)
    |> validate_inclusion(:status, ["pending", "done", "deleted"])
    |> validate_inclusion(:notification_type, ["popup", "email", "sms"])
    |> validate_inclusion(:recurring_type, ["none", "daily", "weekly", "monthly"])
    |> validate_inclusion(:priority, ["low", "medium", "high", "urgent"])
    |> validate_future_date(:scheduled_at)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for global reminder updates.
  """
  def update_changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:title, :description, :scheduled_at, :notification_type, :recurring_type, :priority])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:description, max: 1000)
    |> validate_inclusion(:notification_type, ["popup", "email", "sms"])
    |> validate_inclusion(:recurring_type, ["none", "daily", "weekly", "monthly"])
    |> validate_inclusion(:priority, ["low", "medium", "high", "urgent"])
    |> validate_future_date(:scheduled_at)
  end

  @doc """
  Creates a changeset for marking as done.
  """
  def mark_done_changeset(reminder) do
    change(reminder,
      status: "done",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end

  @doc """
  Creates a changeset for soft deletion.
  """
  def delete_changeset(reminder) do
    change(reminder, status: "deleted")
  end

  @doc """
  Creates a changeset for recurring reminder.
  """
  def recurring_changeset(reminder, next_scheduled_date) do
    reminder
    |> change(status: "pending")
    |> put_change(:scheduled_at, next_scheduled_date)
    |> put_change(:completed_at, nil)
  end

  # Validação customizada para data futura
  defp validate_future_date(changeset, field) do
    validate_change(changeset, field, fn _, scheduled_at ->
      now = DateTime.utc_now()

      if DateTime.compare(scheduled_at, now) == :lt do
        [{field, "must be in the future"}]
      else
        []
      end
    end)
  end
end
