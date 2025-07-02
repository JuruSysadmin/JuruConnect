defmodule App.Repo.Migrations.CreateMessagesTable do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :text, :string
      add :sender, :string
      add :chat_id, :string, null: false
      timestamps()
    end

    create index(:messages, [:chat_id])
  end
end
