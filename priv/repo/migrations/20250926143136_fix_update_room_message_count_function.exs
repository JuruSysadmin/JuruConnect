defmodule App.Repo.Migrations.FixUpdateRoomMessageCountFunction do
  use Ecto.Migration

  def up do
    # Remover o trigger primeiro
    execute "DROP TRIGGER IF EXISTS trigger_update_room_message_count ON messages;"

    # Remover a função problemática
    execute "DROP FUNCTION IF EXISTS update_room_message_count();"

    # Recriar a função com treaty_id em vez de order_id
    execute """
    CREATE OR REPLACE FUNCTION update_room_message_count()
    RETURNS TRIGGER AS $$
    BEGIN
        -- Esta função não faz nada por enquanto
        -- Pode ser implementada no futuro se necessário
        RETURN COALESCE(NEW, OLD);
    END;
    $$ LANGUAGE plpgsql;
    """

    # Recriar o trigger
    execute """
    CREATE TRIGGER trigger_update_room_message_count
        AFTER INSERT OR UPDATE OR DELETE ON messages
        FOR EACH ROW
        EXECUTE FUNCTION update_room_message_count();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS trigger_update_room_message_count ON messages;"
    execute "DROP FUNCTION IF EXISTS update_room_message_count();"
  end
end
