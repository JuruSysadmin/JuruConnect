defmodule App.Treaties.TreatyAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "treaty_attachments" do
    field :filename, :string
    field :treaty_id, Ecto.UUID
    field :uploaded_by, Ecto.UUID
    field :original_filename, :string
    field :file_size, :integer
    field :mime_type, :string
    field :file_url, :string
    field :file_type, :string
    field :upload_status, :string
    field :thumbnail_url, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(treaty_attachment, attrs) do
    treaty_attachment
    |> cast(attrs, [:treaty_id, :uploaded_by, :filename, :original_filename, :file_size, :mime_type, :file_url, :file_type, :upload_status, :thumbnail_url])
    |> validate_required([:treaty_id, :uploaded_by, :filename, :original_filename, :file_size, :mime_type, :file_url, :file_type, :upload_status, :thumbnail_url])
  end
end
