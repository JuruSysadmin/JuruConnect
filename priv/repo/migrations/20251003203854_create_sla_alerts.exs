defmodule App.Repo.Migrations.CreateSlaAlerts do
  use Ecto.Migration

  def change do
    create table(:sla_alerts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :treaty_id, references(:treaties, on_delete: :delete_all, type: :binary_id)
      add :category, :string, null: false
      add :priority, :string, null: false
      add :sla_hours, :integer, null: false
      add :warning_hours, :integer, null: false
      add :critical_hours, :integer, null: false
      add :status, :string, default: "active", null: false
      add :alerted_at, :utc_datetime
      add :resolved_at, :utc_datetime
      add :alert_type, :string
      add :escalated_at, :utc_datetime
      add :escalated_to, :string
      add :created_by, references(:users, on_delete: :nilify_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:sla_alerts, [:treaty_id])
    create index(:sla_alerts, [:status])
    create index(:sla_alerts, [:category])
    create index(:sla_alerts, [:priority])
    create index(:sla_alerts, [:alerted_at])
    create index(:sla_alerts, [:created_by])
    create index(:sla_alerts, [:status, :alerted_at])
  end
end
