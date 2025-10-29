defmodule App.Dashboard.DataFetcher do
  @moduledoc """
  Responsável apenas por buscar dados da API externa.
  Separado do DataServer para seguir Single Responsibility Principle.

  ## Responsabilidades
  - Busca dados de vendas diárias e mensais da API
  - Busca dados de empresas/lojas da API
  - Faz merge dos dados de diferentes endpoints
  - Calcula ticket médio de todas as lojas
  - Fornece dados consolidados para o dashboard

  ## Fluxo de Dados
  1. Busca dados de vendas (`dashboard/sale`)
  2. Busca dados de empresas (`dashboard/sale/company`)
  3. Calcula ticket médio das empresas
  4. Faz merge dos dados em um único mapa
  5. Retorna dados consolidados para o Dashboard
  """

  use GenServer
  require Logger

  alias App.ApiClient

  @doc """
  Inicia o GenServer do DataFetcher.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Busca todos os dados do dashboard da API.

  ## Retorno
  - `{:ok, data}` - Dados consolidados do dashboard
  - `{:error, reason}` - Erro ao buscar dados

  ## Timeout
  Usa o timeout configurado em `App.Config.api_timeout_ms()`
  """
  def fetch_dashboard_data do
    GenServer.call(__MODULE__, :fetch_data, App.Config.api_timeout_ms())
  end

  @impl GenServer
  def init(_opts) do
    {:ok, %{}}
  end

  @impl GenServer
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

  @doc false
  @spec fetch_and_merge_dashboard_data() :: {:ok, map()} | {:error, any()}
  defp fetch_and_merge_dashboard_data do
    with {:ok, sale_data} <- ApiClient.fetch_dashboard_summary(),
         {:ok, company_result} <- ApiClient.fetch_companies_data() do
      companies = Map.get(company_result, :companies, [])
      percentual_sale = Map.get(company_result, :percentualSale, 0.0)

      # sale_data já tem ticket_medio calculado por fetch_dashboard_summary
      # Merge dos dados de vendas com dados de empresas para uso em outras partes do dashboard
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
