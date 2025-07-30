defmodule App.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :color, :string, null: false
      add :description, :text
      add :is_active, :boolean, default: true, null: false
      add :created_by, :uuid, null: false
      add :store_id, :uuid

      timestamps()
    end

    # Índices para performance
    create index(:tags, [:name])
    create index(:tags, [:store_id])
    create index(:tags, [:is_active])
    create unique_index(:tags, [:name, :store_id], name: :tags_name_store_id_unique_index)

    # Tabela de relacionamento entre pedidos e tags
    create table(:order_tags, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :order_id, :string, null: false
      add :tag_id, references(:tags, type: :uuid, on_delete: :delete_all), null: false
      add :added_by, :uuid, null: false
      add :added_at, :utc_datetime, null: false

      timestamps()
    end

    # Índices para a tabela de relacionamento
    create index(:order_tags, [:order_id])
    create index(:order_tags, [:tag_id])
    create index(:order_tags, [:added_by])
    create unique_index(:order_tags, [:order_id, :tag_id], name: :order_tags_order_id_tag_id_unique_index)
  end
end
