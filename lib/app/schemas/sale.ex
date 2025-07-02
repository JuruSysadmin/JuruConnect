defmodule App.Schemas.Sale do
  @moduledoc """
  Schema para armazenar vendas individuais do sistema.

  Armazena vendas reais vindas da API externa do sistema corporativo.
  Cada registro representa uma venda individual com dados completos
  incluindo vendedor, loja, valor, meta e timestamps.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
    id: integer(),
    seller_name: String.t(),
    store: String.t(),
    sale_value: Decimal.t(),
    objetivo: Decimal.t(),
    timestamp: DateTime.t(),
    type: atom(),
    product: String.t() | nil,
    category: String.t() | nil,
    brand: String.t() | nil,
    status: String.t() | nil,
    celebration_id: integer() | nil,
    inserted_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  schema "sales" do
    field :seller_name, :string
    field :store, :string
    field :sale_value, :decimal
    field :objetivo, :decimal
    field :timestamp, :utc_datetime
    field :type, Ecto.Enum, values: [:sale_supervisor, :api]
    field :product, :string
    field :category, :string
    field :brand, :string
    field :status, :string
    field :celebration_id, :integer

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(sale, attrs) do
    sale
    |> cast(attrs, [
      :seller_name, :store, :sale_value, :objetivo, :timestamp,
      :type, :product, :category, :brand, :status, :celebration_id
    ])
    |> validate_required([:seller_name, :store, :sale_value, :timestamp, :type])
    |> validate_number(:sale_value, greater_than: 0)
    |> validate_number(:objetivo, greater_than_or_equal_to: 0)
    |> validate_length(:seller_name, max: 255)
    |> validate_length(:store, max: 255)
  end
end
