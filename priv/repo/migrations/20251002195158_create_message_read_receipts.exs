defmodule App.Repo.Migrations.CreateMessageReadReceipts do
  use Ecto.Migration

  def change do
    create table(:message_read_receipts, primary_key: false) do
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :read_at, :utc_datetime_usec
      add :treaty_id, references(:treaties, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime_usec)
    end


    # Índices para performance
    create index(:message_read_receipts, [:treaty_id])
    create index(:message_read_receipts, [:user_id])
    create index(:message_read_receipts, [:read_at])
  end
end
