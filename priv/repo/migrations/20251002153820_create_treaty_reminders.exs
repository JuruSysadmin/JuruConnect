defmodule App.Repo.Migrations.CreateTreatyReminders do
  use Ecto.Migration

  def change do
    create table(:treaty_reminders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :treaty_id, references(:treaties, type: :binary_id), null: false
      add :message, :string, null: false
      add :status, :string, default: "pending", null: false
      add :notified_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:treaty_reminders, [:treaty_id])
    create index(:treaty_reminders, [:status])
    create index(:treaty_reminders, [:inserted_at])

    # Garantir que não há lembretes duplicados pendentes para a mesma tratativa
    create unique_index(:treaty_reminders, [:treaty_id],
      where: "status = 'pending'",
      name: "unique_treaty_pending_reminders")
  end
end
