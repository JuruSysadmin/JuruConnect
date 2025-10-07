defmodule App.Tags.TreatyTag do
  @moduledoc """
  Schema for treaty tags.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "treaty_tags" do
    field :treaty_id, :string
    field :added_by, :binary_id
    field :added_at, :utc_datetime

    belongs_to :tag, App.Tags.Tag

    timestamps()
  end

  @doc """
  Creates a changeset for a treaty tag.

  ## Parameters
    - `treaty_tag`: The treaty tag struct or changeset
    - `attrs`: The attributes to be cast and validated

  ## Returns
    - `%Ecto.Changeset{}` with the changes and validations

  ## Examples
      iex> changeset(%TreatyTag{}, %{treaty_id: "123", tag_id: "456"})
      %Ecto.Changeset{valid?: true, ...}

      iex> changeset(%TreatyTag{}, %{})
      %Ecto.Changeset{valid?: false, errors: [...]}
  """
  def changeset(treaty_tag, attrs) when is_map(attrs) do
    treaty_tag
    |> cast(attrs, [:treaty_id, :tag_id, :added_by, :added_at])
    |> validate_required([:treaty_id, :tag_id, :added_by, :added_at])
    |> validate_length(:treaty_id, min: 1, max: 50)
    |> validate_length(:tag_id, min: 1)
    |> foreign_key_constraint(:tag_id)
    |> unique_constraint([:treaty_id, :tag_id], name: :treaty_tags_treaty_id_tag_id_unique_index)
  end
end
