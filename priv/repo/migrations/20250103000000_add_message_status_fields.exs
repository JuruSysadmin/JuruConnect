defmodule App.Repo.Migrations.AddMessageStatusFields do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :status, :string, default: "sent"
      add :delivered_at, :utc_datetime
      add :read_at, :utc_datetime
      add :read_by, {:array, :string}, default: []
      add :delivered_to, {:array, :string}, default: []
    end

    # Índices para performance de consultas de status
    create index(:messages, [:status])
  end
end
