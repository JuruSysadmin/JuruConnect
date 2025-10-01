defmodule App.Repo.Migrations.AddCategoryToTreaties do
  use Ecto.Migration

  def change do
    alter table(:treaties) do
      add :category, :string, default: "COMERCIAL"
    end
  end
end
