defmodule App.Schemas.DailySalesHistory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "daily_sales_history" do
    field :date, :date
    field :total_sales, :float
    belongs_to :store, App.Stores.Store, type: :binary_id

    timestamps()
  end

  def changeset(history, attrs) do
    history
    |> cast(attrs, [:date, :total_sales, :store_id])
    |> validate_required([:date, :total_sales])
    |> unique_constraint([:date, :store_id])
  end
end
