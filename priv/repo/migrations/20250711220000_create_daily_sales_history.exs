defmodule App.Repo.Migrations.CreateDailySalesHistory do
  use Ecto.Migration

  def change do
    create table(:daily_sales_history) do
      add :date, :date, null: false
      add :total_sales, :float, null: false
      add :store_id, references(:stores, type: :binary_id), null: true

      timestamps()
    end

    create unique_index(:daily_sales_history, [:date, :store_id])
  end
end
