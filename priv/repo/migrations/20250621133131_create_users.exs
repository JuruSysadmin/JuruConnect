defmodule App.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string, null: false
      add :name, :string, null: false
      add :role, :string, null: false
      add :store_id, :binary_id, null: false
      add :password_hash, :string, null: false

      timestamps()
    end

    create index(:users, [:username])
  end
end
