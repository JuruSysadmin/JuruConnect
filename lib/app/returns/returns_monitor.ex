defmodule App.Returns.ReturnsMonitor do
  @moduledoc """
  Monitor que verifica periodicamente novos retornos (devoluções) via API.

  Detecta quando há novos retornos e notifica via PubSub.
  """

  use GenServer
  require Logger

  alias App.{ApiClient, Config}
  alias App.Dashboard.EventBroadcaster

  @polling_interval 30_000
  @default_days 30

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Inicia o polling de retornos.
  """
  def start_polling do
    GenServer.cast(__MODULE__, :start_polling)
  end

  @doc """
  Para o polling de retornos.
  """
  def stop_polling do
    GenServer.cast(__MODULE__, :stop_polling)
  end

  @doc """
  Retorna o status do monitor.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @impl true
  def init(_opts) do
    Logger.info("ReturnsMonitor initialized - starting polling")

    initial_state = %{
      polling: true,
      last_check: nil,
      last_returns_count: 0,
      last_returns_ids: MapSet.new(),
      error_count: 0
    }

    # Inicia o polling automaticamente
    schedule_check()

    {:ok, initial_state}
  end

  @impl true
  def handle_cast(:start_polling, state) do
    if not state.polling do
      schedule_check()
      Logger.info("ReturnsMonitor: Polling started")
      {:noreply, %{state | polling: true}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:stop_polling, state) do
    Logger.info("ReturnsMonitor: Polling stopped")
    {:noreply, %{state | polling: false}}
  end

  @impl true
  def handle_info(:check_returns, state) do
    if state.polling do
      new_state = check_for_new_returns(state)
      schedule_check()
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = build_status(state)
    {:reply, status, state}
  end

  defp build_status(%{last_returns_ids: ids} = state) do
    %{
      polling: state.polling,
      last_check: state.last_check,
      last_returns_count: state.last_returns_count,
      error_count: state.error_count,
      tracking_ids: MapSet.size(ids)
    }
  end

  defp check_for_new_returns(state) do
    Logger.debug("Checking for new returns...")

    case fetch_returns() do
      {:ok, returns_data} ->
        process_returns_data(state, returns_data)

      {:error, reason} ->
        handle_fetch_error(state, reason)
    end
  end

  defp process_returns_data(state, returns_data) do
    current_count = count_total_returns(returns_data)
    current_ids = extract_return_ids(returns_data)

    updated_state = %{
      state |
      last_check: DateTime.utc_now(),
      last_returns_count: current_count,
      last_returns_ids: current_ids,
      error_count: 0
    }

    maybe_notify_new_returns(state, current_count, current_ids, returns_data)

    updated_state
  end

  defp maybe_notify_new_returns(state, current_count, current_ids, returns_data)
       when current_count > state.last_returns_count do
    new_returns = find_new_returns(current_ids, state.last_returns_ids)

    maybe_send_notification(new_returns, returns_data)
  end

  defp maybe_notify_new_returns(_state, _current_count, _current_ids, _returns_data), do: :ok

  defp maybe_send_notification(new_returns, returns_data) do
    if MapSet.size(new_returns) > 0 do
      Logger.info("New returns detected: #{MapSet.size(new_returns)} new return(s)")
      notify_new_returns(returns_data, new_returns)
    else
      :ok
    end
  end

  defp handle_fetch_error(state, reason) do
    Logger.error("Failed to fetch returns: #{inspect(reason)}")
    %{
      state |
      last_check: DateTime.utc_now(),
      error_count: state.error_count + 1
    }
  end

  defp fetch_returns do
    url = "#{Config.api_urls().dashboard_returns}?days=#{@default_days}"
    timeout_opts = [timeout: Config.api_timeout_ms(), recv_timeout: Config.api_timeout_ms()]

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- HTTPoison.get(url, [], timeout_opts),
         {:ok, data} <- Jason.decode(body) do
      {:ok, data}
    else
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "API returned status #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Connection error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "JSON decode error: #{inspect(reason)}"}
    end
  end

  defp count_total_returns(returns_data) when is_list(returns_data) and length(returns_data) > 0 do
    Enum.reduce(returns_data, 0, fn day_data, acc ->
      returns = Map.get(day_data, "returns", [])
      acc + length(returns)
    end)
  end

  defp count_total_returns(_), do: 0

  defp extract_return_ids(returns_data) when is_list(returns_data) and length(returns_data) > 0 do
    returns_data
    |> Enum.flat_map(&Map.get(&1, "returns", []))
    |> Enum.filter(&Map.has_key?(&1, "returnId"))
    |> Enum.map(&Map.get(&1, "returnId"))
    |> MapSet.new()
  end

  defp extract_return_ids(_), do: MapSet.new()

  defp find_new_returns(current_ids, last_ids) do
    MapSet.difference(current_ids, last_ids)
  end

  defp notify_new_returns(returns_data, new_return_ids) do
    new_returns_list = filter_new_returns(returns_data, new_return_ids)

    summary = %{
      count: length(new_returns_list),
      return_ids: MapSet.to_list(new_return_ids),
      timestamp: DateTime.utc_now(),
      returns: new_returns_list
    }

    EventBroadcaster.broadcast_new_returns(summary)
  end

  defp filter_new_returns(returns_data, new_return_ids) when is_list(returns_data) do
    if MapSet.size(new_return_ids) > 0 do
      returns_data
      |> Enum.flat_map(&Map.get(&1, "returns", []))
      |> Enum.filter(&should_include_return?(&1, new_return_ids))
    else
      []
    end
  end

  defp filter_new_returns(_, _), do: []

  defp should_include_return?(return, new_return_ids) do
    case Map.get(return, "returnId") do
      return_id when is_integer(return_id) -> MapSet.member?(new_return_ids, return_id)
      _ -> false
    end
  end

  defp schedule_check do
    Process.send_after(self(), :check_returns, @polling_interval)
  end
end
