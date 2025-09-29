defmodule App.Repo.Migrations.AddTreatyRatingsAndTracking do
  use Ecto.Migration

  def change do
    # Adicionar campos de tracking e encerramento às tratativas
    alter table(:treaties) do
      add :closed_at, :utc_datetime
      add :closed_by, references(:users, type: :binary_id)
      add :close_reason, :string
      add :resolution_notes, :text
    end

    # Criar tabela de ratings das tratativas
    create table(:treaty_ratings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :treaty_id, references(:treaties, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :rating, :integer, null: false # 1-5 estrelas
      add :comment, :text
      add :rated_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:treaty_ratings, [:treaty_id, :user_id])
    create index(:treaty_ratings, [:treaty_id])
    create index(:treaty_ratings, [:user_id])
    create index(:treaty_ratings, [:rating])

    # Criar tabela de tracking de atividades das tratativas
    create table(:treaty_activities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :treaty_id, references(:treaties, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :activity_type, :string, null: false # created, status_changed, message_sent, closed, reopened, etc.
      add :description, :text
      add :metadata, :map # JSON para dados adicionais
      add :activity_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:treaty_activities, [:treaty_id])
    create index(:treaty_activities, [:user_id])
    create index(:treaty_activities, [:activity_type])
    create index(:treaty_activities, [:activity_at])
  end
end
