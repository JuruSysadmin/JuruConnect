defmodule App.Repo.Migrations.CreateTreatyAttachments do
  use Ecto.Migration

  def change do
    create table(:treaty_attachments) do
      add :treaty_id, :uuid
      add :uploaded_by, :uuid
      add :filename, :string
      add :original_filename, :string
      add :file_size, :integer
      add :mime_type, :string
      add :file_url, :string
      add :file_type, :string
      add :upload_status, :string
      add :thumbnail_url, :string

      timestamps(type: :utc_datetime)
    end
  end
end
