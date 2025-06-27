defmodule App.DashboardDataServer do
  use GenServer

  alias App.ApiClient

  @fetch_interval 1000 # 1 segundo

  # API pública
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_data do
    GenServer.call(__MODULE__, :get_data)
  end

  # Callbacks
  @impl true
  def init(_init_arg) do
    schedule_fetch()
    {:ok, %{data: nil, last_update: nil, api_status: :init, api_error: nil}}
  end

  @impl true
  def handle_info(:fetch, state) do
    now = DateTime.utc_now()
    new_state =
      case fetch_all_data() do
        {:ok, data} ->
          Phoenix.PubSub.broadcast(App.PubSub, "dashboard:updated", {:dashboard_updated, data})
          %{state |
            data: data,
            last_update: now,
            api_status: :ok,
            api_error: nil
          }
        {:error, reason} ->
          %{state |
            api_status: :error,
            api_error: reason,
            last_update: now
          }
      end
    schedule_fetch() # Garante que o próximo fetch será agendado
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_data, _from, state) do
    {:reply, state, state}
  end

  defp schedule_fetch do
    Process.send_after(self(), :fetch, @fetch_interval)
  end

  defp fetch_all_data do
    with {:ok, summary} <- App.ApiClient.fetch_dashboard_summary(),
         {:ok, companies} <- App.ApiClient.fetch_companies_data() do
      # Verifica se alguma loja atingiu a meta do dia
      check_daily_goals_achieved(companies)

      data = Map.put(summary, "companies", companies)
      {:ok, data}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_daily_goals_achieved(companies) do
    companies
    |> Enum.each(fn company ->
      daily_percentage = (company.venda_dia / company.meta_dia) * 100

      # Verifica se atingiu exatamente 100% (com margem de 0.1% para evitar múltiplos disparos)
      if daily_percentage >= 100.0 and daily_percentage <= 100.1 do
        # Dispara evento de meta atingida
        Phoenix.PubSub.broadcast(
          App.PubSub,
          "dashboard:goals",
          {:daily_goal_achieved, %{
            store_name: company.nome,
            supervisor_id: company.supervisor_id,
            target: company.meta_dia,
            achieved: company.venda_dia,
            percentage: daily_percentage,
            timestamp: DateTime.utc_now()
          }}
        )

        # Log para acompanhamento
        IO.puts("🎉 META DIA ATINGIDA! #{company.nome} - #{AppWeb.DashboardUtils.format_money(company.venda_dia)}")
      end
    end)
  end
end
