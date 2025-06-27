defmodule App.Repo.Migrations.AddImageUrlToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :image_url, :string
    end
  end
end
