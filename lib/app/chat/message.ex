defmodule App.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  @derive {Jason.Encoder, only: [:id, :text, :sender_id, :sender_name, :treaty_id, :tipo, :inserted_at, :image_url, :timestamp, :attachments]}
  schema "messages" do
    field :text,        :string
    field :sender_id,   :string
    field :sender_name, :string
    field :treaty_id,   :string
    field :tipo,        :string, default: "mensagem"
    field :image_url,   :string
    field :timestamp,   :utc_datetime
    field :attachments, {:array, :map}, virtual: true, default: []
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for a message.
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:text, :sender_id, :sender_name, :treaty_id, :tipo, :image_url, :timestamp])
    |> validate_required([:sender_name, :treaty_id])
    |> validate_length(:text, max: 2000)
    |> validate_length(:sender_name, min: 1, max: 100)
    |> validate_inclusion(:tipo, ["mensagem", "sistema", "notificacao"])
    |> put_timestamp()
  end

  # Helper function to set timestamp if not provided
  defp put_timestamp(changeset) do
    case get_change(changeset, :timestamp) do
      nil -> put_change(changeset, :timestamp, DateTime.utc_now())
      _ -> changeset
    end
  end
end
