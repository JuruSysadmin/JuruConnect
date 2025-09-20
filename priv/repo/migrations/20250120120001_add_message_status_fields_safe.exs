defmodule App.Repo.Migrations.AddMessageStatusFieldsSafe do
  use Ecto.Migration

  def change do
    # Verificar se as colunas já existem antes de adicioná-las
    execute """
    DO $$
    BEGIN
        -- Adicionar delivery_status se não existir
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_name = 'messages' AND column_name = 'delivery_status') THEN
            ALTER TABLE messages ADD COLUMN delivery_status VARCHAR(255) DEFAULT 'sent' NOT NULL;
        END IF;

        -- Adicionar read_status se não existir
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_name = 'messages' AND column_name = 'read_status') THEN
            ALTER TABLE messages ADD COLUMN read_status VARCHAR(255) DEFAULT 'unread' NOT NULL;
        END IF;

        -- Adicionar read_at se não existir
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_name = 'messages' AND column_name = 'read_at') THEN
            ALTER TABLE messages ADD COLUMN read_at TIMESTAMP(6);
        END IF;

        -- Adicionar read_by se não existir
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_name = 'messages' AND column_name = 'read_by') THEN
            ALTER TABLE messages ADD COLUMN read_by VARCHAR(255);
        END IF;

        -- Adicionar delivered_at se não existir
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_name = 'messages' AND column_name = 'delivered_at') THEN
            ALTER TABLE messages ADD COLUMN delivered_at TIMESTAMP(6);
        END IF;

        -- Adicionar viewed_by se não existir
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_name = 'messages' AND column_name = 'viewed_by') THEN
            ALTER TABLE messages ADD COLUMN viewed_by TEXT;
        END IF;
    END $$;
    """, ""

    # Criar índices se não existirem
    execute """
    DO $$
    BEGIN
        -- Índice para delivery_status
        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'messages_delivery_status_index') THEN
            CREATE INDEX messages_delivery_status_index ON messages (delivery_status);
        END IF;

        -- Índice para read_status
        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'messages_read_status_index') THEN
            CREATE INDEX messages_read_status_index ON messages (read_status);
        END IF;

        -- Índice para read_at
        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'messages_read_at_index') THEN
            CREATE INDEX messages_read_at_index ON messages (read_at);
        END IF;

        -- Índice composto para order_id e read_status
        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'messages_order_id_read_status_index') THEN
            CREATE INDEX messages_order_id_read_status_index ON messages (order_id, read_status);
        END IF;
    END $$;
    """, ""
  end
end
