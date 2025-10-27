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
  @call_timeout App.Config.api_timeout_ms()

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_data(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @call_timeout)
    cache_key = "dashboard_data"

    with {:error, _} <- CacheManager.get(cache_key),
         {:ok, data} <- DataStore.get_data(timeout) do
      CacheManager.put(cache_key, data, 30_000)
      {:ok, data}
    else
      {:ok, cached_data} ->
        Logger.debug("Dashboard data served from cache")
        {:ok, cached_data}

      other ->
        other
    end
  end

  def get_status do
    DataStore.get_status()
  end

  def status do
    GenServer.call(__MODULE__, :status, 5_000)
  end

  @impl true
  def init(_opts) do
    schedule_next_fetch()

    initial_state = %{
      fetch_count: 0,
      last_fetch_time: nil,
      error_count: 0,
      last_devolution: 0.0
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
  def handle_call(:status, _from, state) do
    status_info = %{
      api_status: DataStore.get_status().api_status,
      last_update: DataStore.get_status().last_update,
      fetch_count: state.fetch_count,
      has_data: DataStore.get_status().has_data
    }

    {:reply, status_info, state}
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
            current_devolution = extract_devolution_value(processed_data)
            handle_devolution_change(current_devolution, state.last_devolution)

            App.CelebrationManager.process_api_data(processed_data)

            DataStore.update_data(processed_data)

            CacheManager.delete("dashboard_data")

            EventBroadcaster.broadcast_dashboard_update(processed_data)
            EventBroadcaster.broadcast_system_status(:ok, "Data updated successfully")

            %{
              state |
              fetch_count: state.fetch_count + 1,
              last_fetch_time: DateTime.utc_now(),
              error_count: 0,
              last_devolution: current_devolution
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

  defp extract_devolution_value(data) do
    case data do
      %{"devolution" => v} when is_number(v) -> v
      %{devolution: v} when is_number(v) -> v
      _ -> 0.0
    end
  end

  defp handle_devolution_change(current, last) when current > last do
    Logger.info("Nova devolução registrada: anterior=#{:erlang.float_to_binary(last * 1.0, decimals: 2)}, atual=#{:erlang.float_to_binary(current * 1.0, decimals: 2)}, timestamp=#{DateTime.utc_now()}")
    Phoenix.PubSub.broadcast(App.PubSub, "dashboard:devolucao", {:devolucao_aumentou, %{anterior: last, atual: current}})
  end

  defp handle_devolution_change(_current, _last), do: :ok
end
