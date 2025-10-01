defmodule App.Treaties.TreatyRating do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "treaty_ratings" do
    field :rating, :string
    field :comment, :string
    field :rated_at, :utc_datetime

    # Relacionamentos
    belongs_to :treaty, App.Treaties.Treaty
    belongs_to :user, App.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a treaty rating.
  """
  def changeset(rating, attrs) do
    rating
    |> cast(attrs, [:treaty_id, :user_id, :rating, :comment, :rated_at])
    |> validate_required([:treaty_id, :user_id, :rating, :rated_at])
    |> validate_inclusion(:rating, ["péssimo", "ruim", "bom", "excelente"])
    |> validate_length(:comment, max: 1000)
    |> unique_constraint([:treaty_id, :user_id])
    |> foreign_key_constraint(:treaty_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for creating a new rating.
  """
  def create_changeset(rating, attrs) do
    rating
    |> changeset(attrs)
    |> put_change(:rated_at, DateTime.utc_now())
  end
end
