defmodule App.Dashboard.EventBroadcaster do
  @moduledoc """
  GenServer responsável exclusivamente por gerenciar broadcasts de eventos.
  Centraliza toda a lógica de PubSub e notificações do sistema.
  """

  use GenServer

  @dashboard_topic "dashboard:updated"
  @sales_topic "sales:feed"
  @celebrations_topic "celebrations:new"
  @system_topic "system:status"
  @returns_topic "returns:new"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def broadcast_dashboard_update(data) do
    GenServer.cast(__MODULE__, {:broadcast, @dashboard_topic, {:dashboard_updated, data}})
  end

  def broadcast_new_sale(sale_data) do
    GenServer.cast(__MODULE__, {:broadcast, @sales_topic, {:new_sale, sale_data}})
  end

  def broadcast_celebration(celebration_data) do
    GenServer.cast(__MODULE__, {:broadcast, @celebrations_topic, {:new_celebration, celebration_data}})
  end

  def broadcast_system_status(status, message) do
    GenServer.cast(__MODULE__, {:broadcast, @system_topic, {:status_update, status, message}})
  end

    @doc """
  Faz broadcast de atualização de dados de supervisor para um supervisor específico.
  Tópico dinâmico: "supervisor:<supervisor_id>"
  """
  def broadcast_supervisor_update(supervisor_id, supervisor_data) do
      topic = "supervisor:#{supervisor_id}"
    GenServer.cast(__MODULE__, {:broadcast, topic, {:supervisor_updated, supervisor_data}})
  end

  def broadcast_new_returns(returns_data) do
    GenServer.cast(__MODULE__, {:broadcast, @returns_topic, {:new_returns, returns_data}})
  end

  def subscribe_to_dashboard_updates do
    Phoenix.PubSub.subscribe(App.PubSub, @dashboard_topic)
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl GenServer
  def init(_opts) do
    initial_state = %{
      broadcast_count: 0,
      last_broadcast: nil,
      topic_stats: %{
        @dashboard_topic => 0,
        @sales_topic => 0,
        @celebrations_topic => 0,
        @system_topic => 0,
        @returns_topic => 0
      }
    }

    {:ok, initial_state}
  end

  @impl GenServer
  def handle_cast({:broadcast, topic, message}, state) do
    case Phoenix.PubSub.broadcast(App.PubSub, topic, message) do
      :ok ->
        new_state = %{
          state |
          broadcast_count: state.broadcast_count + 1,
          last_broadcast: DateTime.utc_now(),
          topic_stats: Map.update(state.topic_stats, topic, 1, &(&1 + 1))
        }

        {:noreply, new_state}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_broadcasts: state.broadcast_count,
      last_broadcast: state.last_broadcast,
      topic_stats: state.topic_stats,
      uptime: get_uptime()
    }

    {:reply, stats, state}
  end

  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end
end
