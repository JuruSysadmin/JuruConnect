defmodule App.Repo.Migrations.FixOrderIdReferences do
  use Ecto.Migration

  def up do
    # Verificar e corrigir triggers que ainda referenciam order_id
    execute """
    DO $$
    DECLARE
        trigger_record RECORD;
    BEGIN
        -- Listar todos os triggers que podem estar causando o problema
        FOR trigger_record IN
            SELECT trigger_name, event_object_table, action_statement
            FROM information_schema.triggers
            WHERE event_object_table = 'messages'
        LOOP
            RAISE NOTICE 'Trigger encontrado: % na tabela %', trigger_record.trigger_name, trigger_record.event_object_table;
            RAISE NOTICE 'Action: %', trigger_record.action_statement;
        END LOOP;

        -- Verificar se há funções que referenciam order_id
        FOR trigger_record IN
            SELECT routine_name, routine_definition
            FROM information_schema.routines
            WHERE routine_definition LIKE '%order_id%'
            AND routine_type = 'FUNCTION'
        LOOP
            RAISE NOTICE 'Função que referencia order_id: %', trigger_record.routine_name;
        END LOOP;
    END $$;
    """

    # Tentar remover qualquer trigger problemático
    execute """
    DROP TRIGGER IF EXISTS messages_trigger ON messages;
    """

    execute """
    DROP FUNCTION IF EXISTS messages_trigger_function();
    """

    # Verificar se há constraints problemáticos
    execute """
    DO $$
    DECLARE
        constraint_record RECORD;
    BEGIN
        FOR constraint_record IN
            SELECT tc.constraint_name, tc.table_name, kcu.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name
            WHERE tc.table_name = 'messages'
            AND kcu.column_name = 'order_id'
        LOOP
            RAISE NOTICE 'Constraint problemático: % na tabela % coluna %',
                constraint_record.constraint_name,
                constraint_record.table_name,
                constraint_record.column_name;
        END LOOP;
    END $$;
    """
  end

  def down do
    # Esta migração é apenas para correção, não faz rollback
  end
end
