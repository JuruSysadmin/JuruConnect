defmodule App.Dashboard.Orchestrator do
  @moduledoc """
  Orchestrador principal que coordena todos os módulos do dashboard.
  Implementa o padrão Facade e coordena:
  - DataFetcher: busca dados da API
  - DataStore: armazena e gerencia estado
  - CacheManager: gerencia cache
  - EventBroadcaster: faz broadcasts de eventos
  """

  use GenServer
  require Logger

  alias App.Dashboard.DataFetcher
  alias App.Dashboard.DataStore
  alias App.Dashboard.CacheManager
  alias App.Dashboard.EventBroadcaster

  @fetch_interval 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_data(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    cache_key = "dashboard_data"

    case CacheManager.get(cache_key) do
      {:ok, cached_data} ->
        Logger.debug("Dashboard data served from cache")
        {:ok, cached_data}

      {:error, _} ->
        case DataStore.get_data(timeout) do
          {:ok, data} ->
            CacheManager.put(cache_key, data, 30_000)
            {:ok, data}

          other ->
            other
        end
    end
  end

  def force_refresh do
    GenServer.cast(__MODULE__, :force_refresh)
  end

  def get_status do
    DataStore.get_status()
  end

  def get_cache_stats do
    CacheManager.stats()
  end

  def get_broadcast_stats do
    EventBroadcaster.get_stats()
  end

  @impl true
  def init(_opts) do
    schedule_next_fetch()

    initial_state = %{
      fetch_count: 0,
      last_fetch_time: nil,
      error_count: 0
    }

    Logger.info("Dashboard Orchestrator initialized")
    {:ok, initial_state}
  end

  @impl true
  def handle_info(:fetch_data, state) do
    new_state = perform_data_fetch(state)
    schedule_next_fetch()
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:force_refresh, state) do
    Logger.info("Force refresh requested")
    new_state = perform_data_fetch(state)
    {:noreply, new_state}
  end

  defp perform_data_fetch(state) do
    Logger.debug("Starting data fetch cycle")

    DataStore.update_status(:loading)
    EventBroadcaster.broadcast_system_status(:loading, "Fetching dashboard data")

    case DataFetcher.fetch_dashboard_data() do
      {:ok, raw_data} ->
        Logger.info("Data fetched successfully")

        case process_and_validate_data(raw_data) do
          {:ok, processed_data} ->
            DataStore.update_data(processed_data)

            CacheManager.delete("dashboard_data")

            EventBroadcaster.broadcast_dashboard_update(processed_data)
            EventBroadcaster.broadcast_system_status(:ok, "Data updated successfully")

            %{
              state |
              fetch_count: state.fetch_count + 1,
              last_fetch_time: DateTime.utc_now(),
              error_count: 0
            }

          {:error, reason} ->
            Logger.error("Data processing failed: #{inspect(reason)}")
            handle_fetch_error(state, "Data processing failed: #{reason}")
        end

      {:error, reason} ->
        Logger.error("Data fetch failed: #{inspect(reason)}")
        handle_fetch_error(state, "API fetch failed: #{reason}")
    end
  end

  defp process_and_validate_data(raw_data) do
    case App.Validators.ApiDataValidator.validate_dashboard_data(raw_data) do
      {:ok, validated_data} ->
        {:ok, validated_data}
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, "Processing error: #{inspect(error)}"}
  end

  defp handle_fetch_error(state, reason) do
    DataStore.update_status(:error, reason)
    EventBroadcaster.broadcast_system_status(:error, reason)

    %{
      state |
      fetch_count: state.fetch_count + 1,
      last_fetch_time: DateTime.utc_now(),
      error_count: state.error_count + 1
    }
  end

  defp schedule_next_fetch do
    Process.send_after(self(), :fetch_data, @fetch_interval)
  end
end
