defmodule App.Workers.DailySalesHistoryWorker do
  use Oban.Worker, queue: :default, max_attempts: 3
  alias App.Repo
  alias App.Schemas.DailySalesHistory
  alias App.Sales

  @impl Oban.Worker
  def perform(_job) do
    today = Date.utc_today()
    # Soma o total de vendas do dia
    metrics = Sales.calculate_sales_metrics(date_from: today, date_to: today)
    total_sales = Map.get(metrics, :total_sales, 0.0)

    # Grava na tabela, se ainda não existir
    changeset = DailySalesHistory.changeset(%DailySalesHistory{}, %{
      date: today,
      total_sales: total_sales
    })

    case Repo.insert(changeset, on_conflict: :nothing) do
      {:ok, _} -> :ok
      {:error, _} -> :ok # já existe, ignora
    end
  end
end
