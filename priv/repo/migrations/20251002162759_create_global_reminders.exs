defmodule App.Repo.Migrations.CreateGlobalReminders do
  use Ecto.Migration

  def change do
    create table(:global_reminders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
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
    create index(:global_reminders, [:user_id])
    create index(:global_reminders, [:scheduled_at])
    create index(:global_reminders, [:status])
    create index(:global_reminders, [:priority])
    create index(:global_reminders, [:recurring_type])

    # Índice composto para busca de lembretes pendentes
    create index(:global_reminders, [:status, :scheduled_at])

    # Índice para lembretes por usuário
    create index(:global_reminders, [:user_id, :status])
    create index(:global_reminders, [:user_id, :scheduled_at])

    # Índice para busca de texto
    create index(:global_reminders, [:title])
    create index(:global_reminders, [:description])
  end
end
