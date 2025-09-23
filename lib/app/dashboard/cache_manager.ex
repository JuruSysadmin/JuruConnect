defmodule App.Dashboard.CacheManager do
  @moduledoc """
  GenServer responsável exclusivamente por gerenciar cache dos dados do dashboard.
  Implementa TTL, limpeza automática e estratégias de invalidação.
  """

  use GenServer
  require Logger

  @cache_ttl_ms 30_000
  @cleanup_interval_ms 60_000

  defstruct [
    :cache,
    :stats
  ]

  @type cache_entry :: {term(), DateTime.t()}
  @type cache_stats :: %{
    hits: non_neg_integer(),
    misses: non_neg_integer(),
    evictions: non_neg_integer(),
    hit_rate: float()
  }
  @type state :: %__MODULE__{
    cache: %{String.t() => cache_entry()},
    stats: cache_stats()
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(key) when is_binary(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def put(key, value, ttl \\ @cache_ttl_ms) when is_binary(key) and is_integer(ttl) and ttl > 0 do
    GenServer.cast(__MODULE__, {:put, key, value, ttl})
  end

  def delete(key) when is_binary(key) do
    GenServer.cast(__MODULE__, {:delete, key})
  end

  def clear_all do
    GenServer.cast(__MODULE__, :clear_all)
  end

  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()

    initial_state = %__MODULE__{
      cache: %{},
      stats: %{
        hits: 0,
        misses: 0,
        evictions: 0,
        hit_rate: 0.0
      }
    }

    Logger.info("Dashboard CacheManager initialized")
    {:ok, initial_state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) when is_binary(key) do
    current_time = DateTime.utc_now()

    case Map.get(state.cache, key) do
      {value, expires_at} ->
        if DateTime.before?(current_time, expires_at) do
          new_stats = %{state.stats | hits: state.stats.hits + 1}
          {:reply, {:ok, value}, %{state | stats: new_stats}}
        else
          new_cache = Map.delete(state.cache, key)
          new_stats = %{
            state.stats |
            misses: state.stats.misses + 1,
            evictions: state.stats.evictions + 1
          }

          {:reply, {:error, :expired}, %{state | cache: new_cache, stats: new_stats}}
        end

      nil ->
        new_stats = %{state.stats | misses: state.stats.misses + 1}
        {:reply, {:error, :not_found}, %{state | stats: new_stats}}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    total_requests = state.stats.hits + state.stats.misses
    hit_rate = calculate_hit_rate(state.stats.hits, total_requests)
    stats = %{state.stats | hit_rate: hit_rate}
    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:put, key, value, ttl}, state) when is_binary(key) and is_integer(ttl) and ttl > 0 do
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :millisecond)
    new_cache = Map.put(state.cache, key, {value, expires_at})

    Logger.debug("Cache updated for key: #{key}")
    {:noreply, %{state | cache: new_cache}}
  end

  @impl true
  def handle_cast({:delete, key}, state) when is_binary(key) do
    new_cache = Map.delete(state.cache, key)
    {:noreply, %{state | cache: new_cache}}
  end

  @impl true
  def handle_cast(:clear_all, state) do
    Logger.info("Cache cleared")
    {:noreply, %{state | cache: %{}}}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    current_time = DateTime.utc_now()

    {valid_cache, expired_count} =
      Enum.reduce(state.cache, {%{}, 0}, fn {key, {value, expires_at}}, {acc_cache, count} ->
        if DateTime.before?(current_time, expires_at) do
          {Map.put(acc_cache, key, {value, expires_at}), count}
        else
          {acc_cache, count + 1}
        end
      end)

    if expired_count > 0 do
      Logger.debug("Cleaned #{expired_count} expired cache entries")
    end

    new_stats = %{state.stats | evictions: state.stats.evictions + expired_count}
    schedule_cleanup()

    {:noreply, %{state | cache: valid_cache, stats: new_stats}}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
  end

  defp calculate_hit_rate(hits, total_requests) when total_requests > 0 do
    Float.round(hits / total_requests * 100, 2)
  end

  defp calculate_hit_rate(_hits, _total_requests), do: 0.0

  @impl true
  def terminate(reason, _state) do
    Logger.info("Dashboard CacheManager terminating: #{inspect(reason)}")
    :ok
  end
end
