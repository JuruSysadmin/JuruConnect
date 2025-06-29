defmodule App.Repo.Migrations.CreateSecurityEvents do
  use Ecto.Migration

  def change do
    create table(:security_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :username, :string
      add :session_id, :string
      add :ip_address, :inet
      add :user_agent, :text
      add :success, :boolean, default: false
      add :failure_reason, :string
      add :metadata, :map
      add :severity, :string, default: "info"
      add :timestamp, :utc_datetime_usec, null: false

      timestamps()
    end

    create index(:security_events, [:event_type])
    create index(:security_events, [:user_id])
    create index(:security_events, [:ip_address])
    create index(:security_events, [:timestamp])
    create index(:security_events, [:severity])
    create index(:security_events, [:success])
    create index(:security_events, [:event_type, :timestamp])
    create index(:security_events, [:user_id, :timestamp])
  end
end
