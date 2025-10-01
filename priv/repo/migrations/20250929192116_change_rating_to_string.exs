defmodule App.Repo.Migrations.ChangeRatingToString do
  use Ecto.Migration

  def change do
    alter table(:treaty_ratings) do
      modify :rating, :string
    end
  end
end
