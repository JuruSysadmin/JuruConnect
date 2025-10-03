defmodule App.Repo.Migrations.AddPreviewFieldsToMessageAttachments do
  use Ecto.Migration

  def up do
    alter table(:message_attachments) do
      add_if_not_exists :preview_capable, :boolean, default: false
      add_if_not_exists :language, :string
      add_if_not_exists :metadata, :map, default: %{}
    end
  end

  def down do
    alter table(:message_attachments) do
      remove_if_exists :preview_capable, :boolean
      remove_if_exists :language, :string
      remove_if_exists :metadata, :map
    end
  end
end
