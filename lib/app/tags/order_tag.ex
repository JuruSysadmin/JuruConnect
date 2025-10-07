defmodule App.Tags.OrderTag do
  @moduledoc """
  Schema for order tags.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "order_tags" do
    field :order_id, :string
    field :added_by, :binary_id
    field :added_at, :utc_datetime

    belongs_to :tag, App.Tags.Tag

    timestamps()
  end

  @doc """
  Creates a changeset for an order tag.

  ## Parameters
    - `order_tag`: The order tag struct or changeset
    - `attrs`: The attributes to be cast and validated

  ## Returns
    - `%Ecto.Changeset{}` with the changes and validations

  ## Examples
      iex> changeset(%OrderTag{}, %{order_id: "123", tag_id: "456"})
      %Ecto.Changeset{valid?: true, ...}

      iex> changeset(%OrderTag{}, %{})
      %Ecto.Changeset{valid?: false, errors: [...]}
  """
  def changeset(order_tag, attrs) when is_map(attrs) do
    order_tag
    |> cast(attrs, [:order_id, :tag_id, :added_by, :added_at])
    |> validate_required([:order_id, :tag_id, :added_by, :added_at])
    |> validate_length(:order_id, min: 1, max: 50)
    |> validate_length(:tag_id, min: 1)
    |> foreign_key_constraint(:tag_id)
    |> unique_constraint([:order_id, :tag_id], name: :order_tags_order_id_tag_id_unique_index)
  end
end
