defmodule App.TreatyComments.TreatyComment do
  @moduledoc """
  Schema for treaty comments.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "treaty_comments" do
    field :content, :string
    field :comment_type, :string, default: "internal_note"
    field :status, :string, default: "active"

    # Relacionamentos
    belongs_to :treaty, App.Treaties.Treaty
    belongs_to :user, App.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for treaty comment creation.
  """
  def create_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:treaty_id, :user_id, :content, :comment_type, :status])
    |> validate_required([:treaty_id, :user_id, :content])
    |> validate_length(:content, min: 1, max: 2000)
    |> validate_inclusion(:comment_type, ["internal_note", "public_note"])
    |> validate_inclusion(:status, ["active", "deleted"])
    |> foreign_key_constraint(:treaty_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for treaty comment updates.
  """
  def update_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:content, :status])
    |> validate_length(:content, min: 1, max: 2000)
    |> validate_inclusion(:status, ["active", "deleted"])
  end

  @doc """
  Creates a changeset for soft deletion.
  """
  def delete_changeset(comment) do
    change(comment, status: "deleted")
  end
end
