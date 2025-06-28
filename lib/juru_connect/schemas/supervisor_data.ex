defmodule JuruConnect.Schemas.SupervisorData do
  @moduledoc """
  Schema para armazenar dados de supervisores e vendedores vindos da API.

  Armazena tanto dados agregados quanto dados individuais de cada vendedor
  usando os tipos JSONB do PostgreSQL para flexibilidade.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
    id: integer(),
    objective: Decimal.t(),
    sale: Decimal.t(),
    percentual_sale: float(),
    discount: Decimal.t(),
    nfs: integer(),
    mix: integer(),
    objective_today: Decimal.t(),
    sale_today: Decimal.t(),
    nfs_today: integer(),
    devolution: Decimal.t(),
    objective_hour: Decimal.t(),
    percentual_objective_hour: float(),
    sale_supervisor: map(),
    collected_at: DateTime.t(),
    inserted_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  schema "supervisor_data" do
    field :objective, :decimal
    field :sale, :decimal
    field :percentual_sale, :float
    field :discount, :decimal
    field :nfs, :integer
    field :mix, :integer
    field :objective_today, :decimal
    field :sale_today, :decimal
    field :nfs_today, :integer
    field :devolution, :decimal
    field :objective_hour, :decimal
    field :percentual_objective_hour, :float
    field :objective_total_hour, :decimal
    field :percentual_objective_total_hour, :float
    field :sale_supervisor, {:array, :map}
    field :collected_at, :utc_datetime

    timestamps()
  end

  @doc """
  Changeset para criação de dados de supervisor.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(supervisor_data, attrs) do
    supervisor_data
    |> cast(attrs, [
      :objective, :sale, :percentual_sale, :discount, :nfs, :mix,
      :objective_today, :sale_today, :nfs_today, :devolution,
      :objective_hour, :percentual_objective_hour, :objective_total_hour,
      :percentual_objective_total_hour, :sale_supervisor, :collected_at
    ])
    |> validate_required([
      :objective, :sale, :percentual_sale, :sale_supervisor, :collected_at
    ])
    |> validate_number(:percentual_sale, greater_than_or_equal_to: 0)
    |> validate_number(:nfs, greater_than_or_equal_to: 0)
    |> validate_number(:mix, greater_than_or_equal_to: 0)
  end
end
