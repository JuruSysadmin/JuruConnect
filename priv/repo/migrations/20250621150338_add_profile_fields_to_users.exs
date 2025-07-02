defmodule App.Repo.Migrations.AddProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :website, :string
      add :avatar_url, :string
    end
  end
end
