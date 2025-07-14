defmodule App.Dashboard.DataFetcher do
  @moduledoc """
  Responsável apenas por buscar dados da API externa.
  Separado do DataServer para seguir Single Responsibility Principle.
  """

  use GenServer
  require Logger

  alias App.ApiClient

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def fetch_dashboard_data do
    GenServer.call(__MODULE__, :fetch_data, App.Config.api_timeout_ms())
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call(:fetch_data, _from, state) do
    case fetch_and_merge_dashboard_data() do
      {:ok, data} ->
        Logger.info("Dashboard data fetched successfully")
        {:reply, {:ok, data}, state}
      {:error, reason} ->
        Logger.error("Failed to fetch dashboard data: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  defp fetch_and_merge_dashboard_data do
    with {:ok, sale_data} <- ApiClient.fetch_dashboard_summary(),
         {:ok, company_result} <- ApiClient.fetch_companies_data() do
      companies = Map.get(company_result, :companies, [])
      percentual_sale = Map.get(company_result, :percentualSale, 0.0)

      merged_data =
        Map.merge(sale_data, %{
          "companies" => companies,
          "percentualSale" => percentual_sale
        })

      {:ok, merged_data}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
