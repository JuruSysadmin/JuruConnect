defmodule App.Repo.Migrations.CreateChatReminders do
  use Ecto.Migration

  def change do
    create table(:chat_reminders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :treaty_id, references(:treaties, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false, size: 200
      add :description, :text
      add :scheduled_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
      add :status, :string, default: "pending", null: false
      add :notification_type, :string, default: "popup", null: false
      add :recurring_type, :string, default: "none", null: false
      add :priority, :string, default: "medium", null: false

      timestamps(type: :utc_datetime)
    end

    # Índices para melhor performance
    create index(:chat_reminders, [:user_id])
    create index(:chat_reminders, [:treaty_id])
    create index(:chat_reminders, [:scheduled_at])
    create index(:chat_reminders, [:status])
    create index(:chat_reminders, [:priority])
    create index(:chat_reminders, [:recurring_type])

    # Índices compostos para busca otimizada
    create index(:chat_reminders, [:status, :scheduled_at])
    create index(:chat_reminders, [:user_id, :status])
    create index(:chat_reminders, [:user_id, :scheduled_at])
    create index(:chat_reminders, [:treaty_id, :status])

    # Índices para busca de texto
    create index(:chat_reminders, [:title])
    create index(:chat_reminders, [:description])
  end
end
