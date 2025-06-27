defmodule App.Repo.Migrations.AddFieldsToMessages do
  use Ecto.Migration

  def up do
    # 1. Add new columns, allowing them to be null temporarily
    alter table(:messages) do
      add :order_id, :string, null: true
      add :sender_id, :string, null: true
      add :sender_name, :string, null: true
      add :timestamp, :utc_datetime, null: true
    end

    # 2. (Optional) Backfill data if necessary. Here we assume we can't,
    # so we will just enforce the constraint going forward.
    # If there were a way to derive order_id from chat_id, we would do it here.
    # Ex: execute "UPDATE messages SET order_id = chat_id"

    # 3. Now that existing rows are handled (or ignored), enforce the not-null constraint
    alter table(:messages) do
      modify :order_id, :string, null: false
      modify :sender_id, :string, null: false
      modify :sender_name, :string, null: false
      modify :timestamp, :utc_datetime, null: false, default: fragment("now()")
    end

    # 4. Remove old columns and create new index
    alter table(:messages) do
      remove :sender
      remove :chat_id
    end
    create index(:messages, [:order_id])
    execute "DROP INDEX IF EXISTS messages_chat_id_index"
  end

  def down do
    # Revert the changes in reverse order
    alter table(:messages) do
      add :sender, :string
      add :chat_id, :string, null: false
      remove :order_id
      remove :sender_id
      remove :sender_name
      remove :timestamp
    end
    create index(:messages, [:chat_id])
    drop index(:messages, [:order_id])
  end
end
