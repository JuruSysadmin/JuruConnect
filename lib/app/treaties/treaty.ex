defmodule App.Treaties.Treaty do
  @moduledoc """
  Schema for treaties.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "treaties" do
    field :treaty_code, :string
    field :title, :string
    field :description, :string
    field :status, :string, default: "active"
    field :priority, :string, default: "normal"
    field :category, :string, default: "COMERCIAL"

    # Campos de encerramento
    field :closed_at, :utc_datetime
    field :close_reason, :string
    field :resolution_notes, :string

    # Relacionamentos
    belongs_to :creator, App.Accounts.User, foreign_key: :created_by
    belongs_to :store, App.Accounts.User, foreign_key: :store_id
    belongs_to :closed_by_user, App.Accounts.User, foreign_key: :closed_by

    # Relacionamentos com tags
    has_many :treaty_tags, App.Tags.TreatyTag
    has_many :tags, through: [:treaty_tags, :tag]

    # Relacionamento com mensagens
    has_many :messages, App.Chat.Message, foreign_key: :treaty_id

    # Relacionamentos com ratings e atividades
    has_many :ratings, App.Treaties.TreatyRating
    has_many :activities, App.Treaties.TreatyActivity
    has_many :reminders, App.Treaties.TreatyReminder

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a treaty.
  """
  def changeset(treaty, attrs) do
    treaty
    |> cast(attrs, [:treaty_code, :title, :description, :status, :priority, :category, :created_by, :store_id, :closed_at, :closed_by, :close_reason, :resolution_notes])
    |> validate_required([:title, :description, :created_by, :store_id])
    |> validate_length(:treaty_code, min: 1, max: 50)
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:description, min: 1, max: 2000)
    |> validate_length(:resolution_notes, max: 2000)
    |> validate_inclusion(:status, ["active", "inactive", "completed", "cancelled", "closed"])
    |> validate_inclusion(:priority, ["low", "normal", "high", "urgent"])
    |> validate_inclusion(:category, ["FINANCEIRO", "COMERCIAL", "LOGISTICA"])
    |> validate_inclusion(:close_reason, ["resolved", "cancelled", "duplicate", "invalid", "other"])
    |> unique_constraint(:treaty_code)
  end

  @doc """
  Creates a changeset for creating a new treaty.
  """
  def create_changeset(treaty, attrs) do
    treaty
    |> changeset(attrs)
    |> put_change(:status, "active")
    |> put_change(:priority, "normal")
    |> put_change(:category, Map.get(attrs, :category, "COMERCIAL"))
    |> generate_treaty_code()
  end

  # Gera um código único para a tratativa
  defp generate_treaty_code(changeset) do
    case get_change(changeset, :treaty_code) do
      nil ->
        code = "TRT#{:rand.uniform(999999) |> Integer.to_string() |> String.pad_leading(6, "0")}"
        put_change(changeset, :treaty_code, code)
      _ ->
        changeset
    end
  end
end
