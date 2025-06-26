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
      case App.ApiClient.fetch_dashboard_summary() do
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
end
