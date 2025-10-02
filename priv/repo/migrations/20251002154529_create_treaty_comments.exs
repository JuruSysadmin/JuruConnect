defmodule App.Repo.Migrations.CreateTreatyComments do
  use Ecto.Migration

  def change do
    create table(:treaty_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :treaty_id, references(:treaties, type: :binary_id), null: false
      add :user_id, references(:users, type: :binary_id), null: false
      add :content, :text, null: false
      add :comment_type, :string, default: "internal_note", null: false
      add :status, :string, default: "active", null: false

      timestamps(type: :utc_datetime)
    end

    create index(:treaty_comments, [:treaty_id])
    create index(:treaty_comments, [:user_id])
    create index(:treaty_comments, [:status])
    create index(:treaty_comments, [:comment_type])
    create index(:treaty_comments, [:inserted_at])

    # Índice composto para busca eficiente
    create index(:treaty_comments, [:treaty_id, :status])
    create index(:treaty_comments, [:treaty_id, :comment_type, :status])
  end
end
