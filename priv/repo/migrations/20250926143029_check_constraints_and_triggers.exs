defmodule App.Repo.Migrations.CheckConstraintsAndTriggers do
  use Ecto.Migration

  def up do
    # Verificar constraints que ainda referenciam order_id
    execute """
    DO $$
    BEGIN
      -- Verificar constraints na tabela messages
      IF EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu 
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_name = 'messages' 
        AND kcu.column_name = 'order_id'
      ) THEN
        RAISE NOTICE 'Existem constraints que ainda referenciam order_id na tabela messages';
      ELSE
        RAISE NOTICE 'Não há constraints que referenciem order_id na tabela messages';
      END IF;
      
      -- Verificar triggers
      IF EXISTS (
        SELECT 1 
        FROM information_schema.triggers 
        WHERE event_object_table = 'messages'
        AND action_statement LIKE '%order_id%'
      ) THEN
        RAISE NOTICE 'Existem triggers que ainda referenciam order_id na tabela messages';
      ELSE
        RAISE NOTICE 'Não há triggers que referenciem order_id na tabela messages';
      END IF;
    END $$;
    """
  end

  def down do
    # Esta migração é apenas para verificação, não faz alterações
  end
end