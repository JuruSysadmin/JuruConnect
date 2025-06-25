defmodule App.Repo.Migrations.CreateMessagesTable do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :text, :text, null: false
      add :sender, :string, null: false
      add :order_id, :integer, null: false
      add :image_url, :string
      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:order_id])
  end
end
