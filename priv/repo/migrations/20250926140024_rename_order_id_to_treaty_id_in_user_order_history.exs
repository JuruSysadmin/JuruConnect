defmodule App.Repo.Migrations.RenameOrderIdToTreatyIdInUserOrderHistory do
  use Ecto.Migration

  def change do
    # Renomear coluna order_id para treaty_id na tabela user_order_history
    rename table(:user_order_history), :order_id, to: :treaty_id

    # Atualizar índices
    drop index(:user_order_history, [:order_id])
    create index(:user_order_history, [:treaty_id])

    # Atualizar constraint único
    drop unique_index(:user_order_history, [:user_id, :order_id], name: :user_order_history_user_id_order_id_index)
    create unique_index(:user_order_history, [:user_id, :treaty_id], name: :user_order_history_user_id_treaty_id_index)
  end
end
