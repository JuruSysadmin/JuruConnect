defmodule App.Tags.OrderTag do
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

  @doc false
  def changeset(order_tag, attrs) do
    order_tag
    |> cast(attrs, [:order_id, :tag_id, :added_by, :added_at])
    |> validate_required([:order_id, :tag_id, :added_by, :added_at])
    |> validate_length(:order_id, min: 1, max: 50)
    |> foreign_key_constraint(:tag_id)
    |> unique_constraint([:order_id, :tag_id], name: :order_tags_order_id_tag_id_unique_index)
  end
end
