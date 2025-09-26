defmodule App.Repo.Migrations.CheckMessagesTableStructure do
  use Ecto.Migration

  def up do
    # Verificar se a coluna order_id ainda existe
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'messages' 
        AND column_name = 'order_id'
      ) THEN
        RAISE NOTICE 'Coluna order_id ainda existe na tabela messages';
      ELSE
        RAISE NOTICE 'Coluna order_id não existe na tabela messages';
      END IF;
      
      IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'messages' 
        AND column_name = 'treaty_id'
      ) THEN
        RAISE NOTICE 'Coluna treaty_id existe na tabela messages';
      ELSE
        RAISE NOTICE 'Coluna treaty_id não existe na tabela messages';
      END IF;
    END $$;
    """
  end

  def down do
    # Esta migração é apenas para verificação, não faz alterações
  end
end