defmodule App.Repo.Migrations.CreateRateLimiterData do
  use Ecto.Migration

  def change do
    # Tabela para tentativas de login
    create table(:login_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identifier, :string, null: false  # IP ou username
      add :identifier_type, :string, null: false  # "ip" ou "username"
      add :attempt_count, :integer, default: 1
      add :first_attempt_at, :utc_datetime_usec, null: false
      add :last_attempt_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps()
    end

    # Tabela para bloqueios ativos
    create table(:active_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identifier, :string, null: false  # IP ou username
      add :identifier_type, :string, null: false  # "ip" ou "username"
      add :reason, :string, null: false  # Motivo do bloqueio
      add :blocked_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :metadata, :map  # Dados adicionais sobre o bloqueio

      timestamps()
    end

    # Índices para performance
    create index(:login_attempts, [:expires_at])
    create index(:login_attempts, [:last_attempt_at])
    create unique_index(:login_attempts, [:identifier, :identifier_type])

    create index(:active_blocks, [:expires_at])
    create index(:active_blocks, [:blocked_at])
    create unique_index(:active_blocks, [:identifier, :identifier_type])
  end
end
