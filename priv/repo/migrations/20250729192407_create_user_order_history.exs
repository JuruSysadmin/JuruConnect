defmodule App.Repo.Migrations.CreateUserOrderHistory do
  use Ecto.Migration

  def change do
    create table(:user_order_history, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :order_id, :string, null: false
      add :last_accessed_at, :utc_datetime, null: false
      add :access_count, :integer, default: 1, null: false

      timestamps()
    end

    create index(:user_order_history, [:user_id])
    create index(:user_order_history, [:order_id])
    create index(:user_order_history, [:user_id, :order_id], unique: true)
    create index(:user_order_history, [:last_accessed_at])
  end
end
