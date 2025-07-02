defmodule App.Repo.Migrations.AddMentionsAndRepliesToMessages do
  use Ecto.Migration

  @moduledoc """
  Migration para adicionar funcionalidades de menções (@usuario) e resposta a mensagens.

  Esta migration adiciona os seguintes campos à tabela messages:
  - mentions: array de strings com os usernames mencionados
  - has_mentions: boolean indicando se a mensagem possui menções
  - reply_to: ID da mensagem original (para threads)
  - is_reply: boolean indicando se é uma resposta

  Criado seguindo TDD com documentação completa em português.
  """

  def up do
    alter table(:messages) do
      # Campos para funcionalidade de menções
      add :mentions, {:array, :string}, default: [], null: false
      add :has_mentions, :boolean, default: false, null: false

      # Campos para funcionalidade de resposta/thread
      add :reply_to, :bigint, null: true
      add :is_reply, :boolean, default: false, null: false
    end

    # Índices para performance
    create index(:messages, [:has_mentions])
    create index(:messages, [:reply_to])
    create index(:messages, [:mentions], using: :gin)

    # Índice composto para buscar menções de um usuário específico
    create index(:messages, [:order_id, :has_mentions])

    # Índice para buscar threads (mensagem + respostas)
    create index(:messages, [:reply_to, :inserted_at])

    # Adicionar foreign key constraint
    create constraint(:messages, :reply_to_fkey,
           check: "reply_to IS NULL OR reply_to != id")

    flush()

    # Comentários nas colunas para documentação
    execute """
    COMMENT ON COLUMN messages.mentions IS 'Array de usernames mencionados na mensagem usando @usuario'
    """

    execute """
    COMMENT ON COLUMN messages.has_mentions IS 'Indica se a mensagem contém menções de usuários'
    """

    execute """
    COMMENT ON COLUMN messages.reply_to IS 'ID da mensagem original a qual esta mensagem está respondendo'
    """

    execute """
    COMMENT ON COLUMN messages.is_reply IS 'Indica se esta mensagem é uma resposta a outra mensagem'
    """
  end

  def down do
    # Remover índices
    drop index(:messages, [:reply_to, :inserted_at])
    drop index(:messages, [:order_id, :has_mentions])
    drop index(:messages, [:mentions])
    drop index(:messages, [:reply_to])
    drop index(:messages, [:has_mentions])

    # Remover constraint
    drop constraint(:messages, :reply_to_fkey)

    # Remover colunas
    alter table(:messages) do
      remove :mentions
      remove :has_mentions
      remove :reply_to
      remove :is_reply
    end
  end
end
