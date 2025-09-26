defmodule App.Repo.Migrations.CreateTreaties do
  use Ecto.Migration

  def change do
    create table(:treaties, primary_key: false) do
      add :id, :string, primary_key: true
      add :title, :string
      add :description, :text
      add :status, :string
      add :priority, :string
      add :created_by, :uuid
      add :store_id, :uuid

      timestamps(type: :utc_datetime)
    end
  end
end
