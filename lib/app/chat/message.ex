defmodule App.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset, only: [cast: 3, validate_required: 2, put_change: 3, validate_inclusion: 3]

  @derive {Jason.Encoder, only: [:id, :text, :sender_id, :sender_name, :order_id, :tipo, :inserted_at, :image_url, :delivery_status, :read_status, :read_at, :read_by, :delivered_at, :viewed_by]}
  schema "messages" do
    field :text,            :string
    field :sender_id,       :string
    field :sender_name,     :string
    field :order_id,        :string
    field :tipo,            :string, default: "mensagem"
    field :image_url,       :string
    field :delivery_status, :string, default: "sent"
    field :read_status,     :string, default: "unread"
    field :read_at,         :utc_datetime_usec
    field :read_by,         :string
    field :delivered_at,    :utc_datetime_usec
    field :viewed_by,       :string
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:text, :sender_id, :sender_name, :order_id, :tipo, :image_url, :delivery_status, :read_status, :read_at, :read_by, :delivered_at, :viewed_by])
    |> validate_required([:text, :sender_name, :order_id])
    |> put_change(:image_url, attrs[:image_url] || nil)
    |> put_change(:delivery_status, attrs[:delivery_status] || "sent")
    |> put_change(:read_status, attrs[:read_status] || "unread")
  end

  @doc """
  Changeset para atualizar status de entrega da mensagem.
  """
  def delivery_changeset(message, attrs) do
    message
    |> cast(attrs, [:delivery_status, :delivered_at])
    |> validate_inclusion(:delivery_status, ["sent", "delivered", "failed"])
  end

  @doc """
  Changeset para atualizar status de leitura da mensagem.
  """
  def read_changeset(message, attrs) do
    message
    |> cast(attrs, [:read_status, :read_at, :read_by, :viewed_by])
    |> validate_inclusion(:read_status, ["unread", "read"])
  end
end
