defmodule App.Auth.RateLimiterCleanup do
  @moduledoc """
  Processo para limpeza automática de dados expirados do Rate Limiter.

  Executa periodicamente a limpeza de tentativas de login e bloqueios
  expirados para manter a performance do sistema.
  """

  use GenServer
  require Logger

  alias App.Auth.RateLimiter

  @cleanup_interval_ms 300_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()
    Logger.info("RateLimiter cleanup process started")
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    {deleted_attempts, deleted_blocks} = RateLimiter.cleanup_expired()

    if deleted_attempts + deleted_blocks > 0 do
      Logger.debug("RateLimiter cleanup completed: #{deleted_attempts} attempts, #{deleted_blocks} blocks removed")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
