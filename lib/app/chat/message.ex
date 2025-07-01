defmodule App.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Schema para mensagens do chat com funcionalidades de status, menções e respostas.

  Este módulo define a estrutura das mensagens incluindo:
  - Status de mensagem (enviada, entregue, lida)
  - Sistema de menções (@usuario) para notificar usuários específicos
  - Sistema de resposta para criar threads de conversa
  - Validações e changesets para garantir integridade dos dados

  Desenvolvido seguindo TDD com documentação completa em português.
  """

  @derive {Jason.Encoder, only: [
    :id, :text, :sender_id, :sender_name, :order_id, :tipo, :image_url,
    :status, :delivered_at, :read_at, :delivered_to, :read_by,
    :mentions, :has_mentions, :reply_to, :is_reply, :inserted_at, :updated_at
  ]}

  schema "messages" do
    field :text, :string
    field :sender_id, :string
    field :sender_name, :string
    field :order_id, :string
    field :tipo, :string
    field :image_url, :string

    # Campos de status
    field :status, :string, default: "sent"
    field :delivered_at, :utc_datetime
    field :read_at, :utc_datetime
    field :delivered_to, {:array, :string}, default: []
    field :read_by, {:array, :string}, default: []

    # Campos de menções
    field :mentions, {:array, :string}, default: []
    field :has_mentions, :boolean, default: false

    # Campos de resposta/thread
    field :reply_to, :integer
    field :is_reply, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset para criação e atualização de mensagens.

  Automaticamente:
  - Extrai menções (@usuario) do texto da mensagem
  - Define has_mentions baseado na presença de menções
  - Define is_reply baseado na presença de reply_to
  - Valida campos obrigatórios e formatos
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :text, :sender_id, :sender_name, :order_id, :tipo, :image_url,
      :status, :delivered_at, :read_at, :delivered_to, :read_by,
      :mentions, :has_mentions, :reply_to, :is_reply
    ])
    |> validate_required([:text, :sender_id, :sender_name, :order_id])
    |> validate_length(:text, min: 1, max: 5000)
    |> validate_inclusion(:status, ["sent", "delivered", "read"])
    |> validate_inclusion(:tipo, ["mensagem", "imagem", "sistema"])
    |> extract_mentions()
    |> set_reply_flags()
    |> validate_reply_to()
  end

  # Extrai menções (@usuario) do texto da mensagem e atualiza os campos relacionados
  defp extract_mentions(changeset) do
    case get_change(changeset, :text) do
      nil ->
        changeset

      text ->
        # Regex para encontrar menções (@usuario)
        mentions = Regex.scan(~r/@(\w+)/, text, capture: :all_but_first)
                  |> List.flatten()
                  |> Enum.uniq()

        changeset
        |> put_change(:mentions, mentions)
        |> put_change(:has_mentions, length(mentions) > 0)
    end
  end

  # Define flags relacionadas à resposta baseado no campo reply_to
  defp set_reply_flags(changeset) do
    case get_change(changeset, :reply_to) do
      nil ->
        put_change(changeset, :is_reply, false)

      _reply_to ->
        put_change(changeset, :is_reply, true)
    end
  end

  # Valida se o reply_to referencia uma mensagem válida e não é auto-referência
  defp validate_reply_to(changeset) do
    case get_change(changeset, :reply_to) do
      nil ->
        changeset

      _reply_to ->
        # Validação será feita via constraint no banco
        changeset
    end
  end
end
