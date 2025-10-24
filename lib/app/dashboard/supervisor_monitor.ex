defmodule App.Dashboard.SupervisorMonitor do
  @moduledoc """
  Monitor que busca e faz broadcast de dados de supervisores.
  Mantém o estado de quais supervisores têm modais abertos e atualiza periodicamente.
  """

  use GenServer
  require Logger

  alias App.Dashboard.EventBroadcaster
  alias App.ApiClient

  @update_interval 30_000 # 30 segundos, mesmo intervalo do dashboard

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registra que um supervisor está sendo visualizado (modal aberto)
  """
  def subscribe_supervisor(supervisor_id) do
    GenServer.cast(__MODULE__, {:subscribe, supervisor_id})
  end

  @doc """
  Remove um supervisor da lista de visualização (modal fechado)
  """
  def unsubscribe_supervisor(supervisor_id) do
    GenServer.cast(__MODULE__, {:unsubscribe, supervisor_id})
  end

  @doc """
  Força atualização imediata de um supervisor específico
  """
  def refresh_supervisor(supervisor_id) do
    GenServer.cast(__MODULE__, {:refresh, supervisor_id})
  end

  @impl true
  def init(_opts) do
    schedule_update()

    initial_state = %{
      subscribed_supervisors: MapSet.new(),
      last_update: nil
    }

    Logger.info("SupervisorMonitor initialized")
    {:ok, initial_state}
  end

  @impl true
  def handle_cast({:subscribe, supervisor_id}, state) do
    new_set = MapSet.put(state.subscribed_supervisors, supervisor_id)
    Logger.debug("Subscribed to supervisor: #{supervisor_id}")

    # Atualiza imediatamente ao adicionar
    refresh_supervisor_data(supervisor_id)

    {:noreply, %{state | subscribed_supervisors: new_set}}
  end

  @impl true
  def handle_cast({:unsubscribe, supervisor_id}, state) do
    new_set = MapSet.delete(state.subscribed_supervisors, supervisor_id)
    Logger.debug("Unsubscribed from supervisor: #{supervisor_id}")
    {:noreply, %{state | subscribed_supervisors: new_set}}
  end

  @impl true
  def handle_cast({:refresh, supervisor_id}, state) do
    refresh_supervisor_data(supervisor_id)
    {:noreply, state}
  end

  @impl true
  def handle_info(:update_supervisors, state) do
    Logger.debug("Updating #{MapSet.size(state.subscribed_supervisors)} supervisors")

    state.subscribed_supervisors
    |> Enum.each(&refresh_supervisor_data/1)

    schedule_update()

    {:noreply, %{state | last_update: DateTime.utc_now()}}
  end

  defp refresh_supervisor_data(supervisor_id) do
    case ApiClient.fetch_supervisor_data(supervisor_id) do
      {:ok, supervisor_data} ->
        # Processa celebrações de vendedores que atingiram 100% da meta diária
        App.CelebrationManager.process_supervisor_data(supervisor_id, supervisor_data)

        EventBroadcaster.broadcast_supervisor_update(supervisor_id, supervisor_data)
        Logger.debug("Broadcasted update for supervisor #{supervisor_id}")

      {:error, reason} ->
        Logger.warning("Failed to fetch supervisor #{supervisor_id}: #{inspect(reason)}")
    end
  end

  defp schedule_update do
    Process.send_after(self(), :update_supervisors, @update_interval)
  end
end
