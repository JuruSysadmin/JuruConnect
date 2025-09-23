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
  @cache_ttl 30_000

  defstruct [
    :fetch_count,
    :last_fetch_time,
    :error_count
  ]

  @type state :: %__MODULE__{
    fetch_count: non_neg_integer(),
    last_fetch_time: DateTime.t() | nil,
    error_count: non_neg_integer()
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_data(opts \\ []) when is_list(opts) do
    timeout = Keyword.get(opts, :timeout, App.Config.api_timeout_ms())
    cache_key = "dashboard_data"

    with {:error, _} <- CacheManager.get(cache_key),
         {:ok, data} <- DataStore.get_data(timeout) do
      CacheManager.put(cache_key, data, @cache_ttl)
      {:ok, data}
    else
      {:ok, cached_data} ->
        Logger.debug("Dashboard data served from cache")
        {:ok, cached_data}
      other ->
        other
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

    initial_state = %__MODULE__{
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

    with {:ok, raw_data} <- DataFetcher.fetch_dashboard_data(),
         {:ok, processed_data} <- process_and_validate_data(raw_data) do
      Logger.info("Data fetched and processed successfully")

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
    else
      {:error, reason} ->
        Logger.error("Data fetch/processing failed: #{inspect(reason)}")
        handle_fetch_error(state, "Data operation failed: #{reason}")
    end
  end

  defp process_and_validate_data(raw_data) when is_map(raw_data) do
    App.Validators.ApiDataValidator.validate_dashboard_data(raw_data)
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

  @impl true
  def terminate(reason, _state) do
    Logger.info("Dashboard Orchestrator terminating: #{inspect(reason)}")
    :ok
  end
end
