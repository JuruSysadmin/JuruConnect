defmodule App.Repo.Migrations.CreateSupervisorData do
  @moduledoc """
  Migration para criar tabela de dados de supervisores.

  Utiliza JSONB para armazenar dados flexíveis dos vendedores e índices
  para otimizar consultas por data de coleta.
  """

  use Ecto.Migration

  def change do
    create table(:supervisor_data) do
      add :objective, :decimal, precision: 15, scale: 2
      add :sale, :decimal, precision: 15, scale: 2
      add :percentual_sale, :float
      add :discount, :decimal, precision: 15, scale: 2
      add :nfs, :integer
      add :mix, :integer
      add :objective_today, :decimal, precision: 15, scale: 2
      add :sale_today, :decimal, precision: 15, scale: 2
      add :nfs_today, :integer
      add :devolution, :decimal, precision: 15, scale: 2
      add :objective_hour, :decimal, precision: 15, scale: 2
      add :percentual_objective_hour, :float
      add :objective_total_hour, :decimal, precision: 15, scale: 2
      add :percentual_objective_total_hour, :float
      add :sale_supervisor, :map
      add :collected_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:supervisor_data, [:collected_at])
    create index(:supervisor_data, [:collected_at, :percentual_sale])

    # Índice GIN para queries no JSON
    create index(:supervisor_data, [:sale_supervisor], using: :gin)
  end
end
