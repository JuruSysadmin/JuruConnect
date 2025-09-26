defmodule App.Chat.MessageAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, only: [:id, :message_id, :uploaded_by_id, :filename, :original_filename, :file_size, :mime_type, :file_url, :file_type, :upload_status, :thumbnail_url, :inserted_at]}

  schema "message_attachments" do
    field :message_id, :integer
    field :uploaded_by_id, :binary_id
    field :filename, :string
    field :original_filename, :string
    field :file_size, :integer
    field :mime_type, :string
    field :file_url, :string
    field :file_type, :string
    field :upload_status, :string, default: "completed"
    field :thumbnail_url, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a message attachment.
  """
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:message_id, :uploaded_by_id, :filename, :original_filename, :file_size, :mime_type, :file_url, :file_type, :upload_status, :thumbnail_url])
    |> validate_required([:message_id, :uploaded_by_id, :filename, :original_filename, :file_size, :mime_type, :file_url, :file_type])
    |> validate_length(:filename, max: 255)
    |> validate_length(:original_filename, max: 255)
    |> validate_length(:mime_type, max: 255)
    |> validate_length(:file_url, max: 255)
    |> validate_length(:file_type, max: 255)
    |> validate_inclusion(:upload_status, ["pending", "completed", "failed"])
    |> validate_inclusion(:file_type, ["image", "document", "video", "audio"])
  end

  @doc """
  Creates a changeset for an image attachment.
  """
  def image_changeset(attachment, attrs) do
    attachment
    |> changeset(attrs)
    |> put_change(:file_type, "image")
    |> put_change(:upload_status, "completed")
  end
end
