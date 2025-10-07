defmodule App.Tags.Tag do
  @moduledoc """
  Schema for tags.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tags" do
    field :name, :string
    field :color, :string
    field :description, :string
    field :is_active, :boolean, default: true
    field :created_by, :binary_id
    field :store_id, :binary_id

    has_many :treaty_tags, App.Tags.TreatyTag
    has_many :treaties, through: [:treaty_tags, :treaty]

    timestamps()
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :color, :description, :is_active, :created_by, :store_id])
    |> validate_required([:name, :color, :created_by])
    |> validate_length(:name, min: 2, max: 50)
    |> validate_length(:description, max: 500)
    |> validate_color_format()
    |> unique_constraint([:name, :store_id], name: :tags_name_store_id_unique_index)
  end

  defp validate_color_format(changeset) do
    validate_change(changeset, :color, fn :color, color ->
      if Regex.match?(~r/^#[0-9A-Fa-f]{6}$/, color) do
        []
      else
        [color: "deve ser um código de cor hexadecimal válido (ex: #ff0000)"]
      end
    end)
  end
end
