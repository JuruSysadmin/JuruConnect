defmodule App.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sender_name, :string, null: false
      add :notification_type, :string, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :is_read, :boolean, default: false, null: false
      add :read_at, :utc_datetime
      add :metadata, :map, default: %{}
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id)
      add :treaty_id, references(:treaties, on_delete: :delete_all, type: :binary_id)
      add :message_id, references(:messages, on_delete: :delete_all)
      add :sender_id, references(:users, on_delete: :delete_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:notifications, [:user_id])
    create index(:notifications, [:treaty_id])
    create index(:notifications, [:message_id])
    create index(:notifications, [:sender_id])
    create index(:notifications, [:is_read])
    create index(:notifications, [:notification_type])
    create index(:notifications, [:inserted_at])
    create index(:notifications, [:user_id, :is_read])
  end
end
