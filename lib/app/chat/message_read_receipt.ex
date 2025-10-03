defmodule App.Chat.MessageReadReceipt do
  @moduledoc """
  Representa a confirmação de leitura de uma mensagem por um usuário.

  Tracks quando um usuário leu uma mensagem específica, permitindo verificar
  quem já leu e quem ainda não leu cada mensagem.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "message_read_receipts" do
    # Chave composta: message_id + user_id
    field :message_id, :id, primary_key: true
    field :user_id, :binary_id, primary_key: true

    # Informações adicionais
    field :read_at, :utc_datetime_usec
    field :treaty_id, :binary_id # Para facilitar consultas

    # Relacionamentos
    belongs_to :message, App.Chat.Message, foreign_key: :message_id, define_field: false
    belongs_to :user, App.Accounts.User, foreign_key: :user_id, define_field: false
    belongs_to :treaty, App.Treaties.Treaty, foreign_key: :treaty_id, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Cria um changeset para registro de leitura de mensagem.
  """
  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [:message_id, :user_id, :read_at, :treaty_id])
    |> validate_required([:message_id, :user_id, :treaty_id])
    |> put_change(:read_at, DateTime.utc_now())
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:treaty_id)
    |> unique_constraint([:message_id, :user_id], name: :message_read_receipts_pkey)
  end

  @doc """
  Cria um changeset para registrar uma nova leitura.
  """
  def create_changeset(receipt, attrs) do
    changeset(receipt, attrs)
  end
end
