defmodule App.Notifications.Notification do
  @moduledoc """
  Schema for notifications.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notifications" do
    field :title, :string
    field :metadata, :map, default: %{}
    field :body, :string
    field :sender_name, :string
    field :notification_type, :string
    field :is_read, :boolean, default: false
    field :read_at, :utc_datetime

    # Foreign keys
    belongs_to :user, App.Accounts.User
    belongs_to :treaty, App.Treaties.Treaty
    belongs_to :message, App.Chat.Message, type: :id
    belongs_to :sender, App.Accounts.User, foreign_key: :sender_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:user_id, :treaty_id, :message_id, :sender_id, :sender_name, :notification_type, :title, :body, :is_read, :read_at, :metadata])
    |> validate_required([:user_id, :treaty_id, :sender_name, :notification_type, :title, :body])
    |> validate_inclusion(:notification_type, ["new_message", "mention", "system"])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:treaty_id)
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:sender_id)
  end

  @doc """
  Creates a changeset for a new notification.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  @doc """
  Creates a changeset for marking a notification as read.
  """
  def mark_read_changeset(notification) do
    notification
    |> change(is_read: true, read_at: DateTime.utc_now())
  end
end
