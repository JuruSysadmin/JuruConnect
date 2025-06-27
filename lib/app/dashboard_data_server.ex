defmodule App.DashboardDataServer do
  @moduledoc """
  GenServer para buscar e armazenar dados do dashboard em tempo real.
  """

  use GenServer
  alias App.ApiClient

  @fetch_interval 30_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_data do
    GenServer.call(__MODULE__, :get_data)
  end

  def init(_) do
    IO.puts("DashboardDataServer started - fetch interval: #{@fetch_interval}ms")
    schedule_fetch()

    {:ok,
     %{
       data: nil,
       api_status: :loading,
       api_error: nil,
       last_update: nil,
       fetching: false
     }}
  end

  def handle_info(:fetch, %{fetching: true} = state) do
    {:noreply, state}
  end

  def handle_info(:fetch, state) do
    state = %{state | fetching: true}

    case fetch_dashboard_data() do
      {:ok, data} ->
        new_state = %{
          state
          | data: data,
            api_status: :ok,
            api_error: nil,
            last_update: DateTime.utc_now(),
            fetching: false
        }

        Phoenix.PubSub.broadcast(App.PubSub, "dashboard:updated", data)

        {:noreply, new_state}

      {:error, reason} ->
        new_state = %{
          state
          | api_status: :error,
            api_error: reason,
            last_update: DateTime.utc_now(),
            fetching: false
        }

        {:noreply, new_state}
    end
    |> then(fn result ->
      schedule_fetch()
      result
    end)
  end

  def handle_call(:get_data, _from, state) do
    {:reply, state, state}
  end

  defp schedule_fetch do
    existing_messages = Process.info(self(), :messages) |> elem(1)
    fetch_pending = Enum.any?(existing_messages, &match?(:fetch, &1))

    unless fetch_pending do
      Process.send_after(self(), :fetch, @fetch_interval)
    end
  end

  defp fetch_dashboard_data do
    with {:ok, sale_data} <- ApiClient.fetch_dashboard_summary(),
         {:ok, company_result} <- ApiClient.fetch_companies_data() do
      companies = Map.get(company_result, :companies, [])
      percentual_sale = Map.get(company_result, :percentualSale, 0.0)

      check_goal_achievements(companies)

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

  defp check_goal_achievements(companies) when is_list(companies) do
    Enum.each(companies, &check_company_goal/1)
  end

  defp check_company_goal(company) do
    perc_dia = Map.get(company, :perc_dia, 0.0)

    if perc_dia >= 99.9 and perc_dia <= 100.1 do
      goal_data = %{
        store_name: company.nome,
        achieved: company.venda_dia,
        target: company.meta_dia,
        percentage: perc_dia,
        timestamp: DateTime.utc_now(),
        celebration_id: System.unique_integer([:positive])
      }

      Phoenix.PubSub.broadcast(App.PubSub, "dashboard:goals", {:daily_goal_achieved, goal_data})

      IO.puts(
        "META DIA ATINGIDA! #{company.nome} - #{AppWeb.DashboardUtils.format_money(company.venda_dia)}"
      )
    end
  end
end
