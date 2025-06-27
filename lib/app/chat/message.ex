defmodule App.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset, only: [cast: 3, validate_required: 2, put_change: 3]

  @derive {Jason.Encoder,
           only: [
             :id,
             :text,
             :sender_id,
             :sender_name,
             :order_id,
             :tipo,
             :inserted_at,
             :image_url
           ]}
  schema "messages" do
    field :text, :string
    field :sender_id, :string
    field :sender_name, :string
    field :order_id, :string
    field :tipo, :string, default: "mensagem"
    field :image_url, :string
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:text, :sender_id, :sender_name, :order_id, :tipo, :image_url])
    |> validate_required([:text, :sender_id, :sender_name, :order_id])
    |> put_change(:image_url, attrs[:image_url] || nil)
  end
end
