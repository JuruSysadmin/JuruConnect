defmodule App.Repo.Migrations.CreateSales do
  @moduledoc """
  Migration para criar tabela de vendas individuais.

  Armazena vendas vindas da API externa com índices otimizados para consultas
  por data, vendedor e loja. Suporta diferentes tipos de venda do sistema corporativo.
  """

  use Ecto.Migration

  def change do
    create table(:sales) do
      add :seller_name, :string, null: false
      add :store, :string, null: false
      add :sale_value, :decimal, precision: 15, scale: 2, null: false
      add :objetivo, :decimal, precision: 15, scale: 2, default: 0.0
      add :timestamp, :utc_datetime, null: false
      add :type, :string, null: false, default: "simulated"
      add :product, :string
      add :category, :string
      add :brand, :string
      add :status, :string
      add :celebration_id, :integer

      timestamps()
    end

    # Índices para otimizar consultas
    create index(:sales, [:timestamp])
    create index(:sales, [:type])
    create index(:sales, [:seller_name])
    create index(:sales, [:store])
    create index(:sales, [:timestamp, :type])
    create index(:sales, [:celebration_id])

    # Índice composto para consultas de dashboard
    create index(:sales, [:timestamp, :sale_value])
  end
end
