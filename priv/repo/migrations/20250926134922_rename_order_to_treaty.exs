defmodule App.Repo.Migrations.RenameOrderToTreaty do
  use Ecto.Migration

  def change do
    # Renomear coluna na tabela messages
    rename table(:messages), :order_id, to: :treaty_id

    # Renomear tabela order_tags para treaty_tags
    rename table(:order_tags), to: table(:treaty_tags)
    rename table(:treaty_tags), :order_id, to: :treaty_id

    # Atualizar índices
    drop index(:messages, [:order_id])
    create index(:messages, [:treaty_id])

    # Criar novo índice para treaty_id
    create index(:treaty_tags, [:treaty_id])

    # Atualizar constraint único
    drop unique_index(:treaty_tags, [:order_id, :tag_id], name: :order_tags_order_id_tag_id_unique_index)
    create unique_index(:treaty_tags, [:treaty_id, :tag_id], name: :treaty_tags_treaty_id_tag_id_unique_index)
  end
end
