defmodule App.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def up do
    execute "CREATE TYPE user_role AS ENUM ('admin','manager','clerk')"

    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string, null: false
      add :name, :string, null: false
      add :role, :user_role, null: false
      add :store_id, references(:stores, type: :binary_id, on_delete: :restrict), null: false
      add :password_hash, :string, null: false
      add :website, :string
      add :avatar_url, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:username])
    create index(:users, [:store_id])
    create index(:users, [:store_id, :role])
  end

  def down do
    drop table(:users)
    execute "DROP TYPE user_role"
  end
end
