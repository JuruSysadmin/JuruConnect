defmodule App.HealthCheck do
  @moduledoc """
  Sistema de Health Check para monitorar APIs externas.

  Verifica periodicamente a saúde da API externa e mantém métricas
  de disponibilidade, tempo de resposta e status de erros.
  """

  use GenServer
  require Logger

  @api_base_url "http://10.1.1.212:8065/api/v1"
  @check_interval 60_000  # 1 minuto
  @timeout 10_000         # 10 segundos

  # Estado do health check
  defstruct [
    :api_status,           # :healthy, :unhealthy, :unknown
    :last_check,           # DateTime da última verificação
    :last_success,         # DateTime do último sucesso
    :response_time,        # Tempo de resposta em ms
    :error_count,          # Contador de erros consecutivos
    :success_count,        # Contador de sucessos nas últimas 24h
    :total_checks,         # Total de verificações
    :uptime_percentage,    # Porcentagem de uptime
    :last_error,           # Último erro encontrado
    :endpoints_status      # Status individual de cada endpoint
  ]

  ## API Pública

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  def check_now do
    GenServer.cast(__MODULE__, :check_now)
  end

  def get_detailed_status do
    GenServer.call(__MODULE__, :get_detailed_status)
  end

  ## Callbacks do GenServer

  @impl true
  def init(_) do
    # Primeira verificação imediata
    send(self(), :perform_check)

    initial_state = %__MODULE__{
      api_status: :unknown,
      last_check: nil,
      last_success: nil,
      response_time: nil,
      error_count: 0,
      success_count: 0,
      total_checks: 0,
      uptime_percentage: 0.0,
      last_error: nil,
      endpoints_status: %{}
    }

    Logger.info("HealthCheck system started")
    {:ok, initial_state}
  end

  @impl true
  def handle_info(:perform_check, state) do
    new_state = perform_health_check(state)
    schedule_next_check()

    # Broadcast do status para interessados
    Phoenix.PubSub.broadcast(
      App.PubSub,
      "health_check:status",
      {:health_status_updated, format_status_for_broadcast(new_state)}
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    simple_status = %{
      status: state.api_status,
      last_check: state.last_check,
      response_time: state.response_time,
      uptime_percentage: state.uptime_percentage,
      error_count: state.error_count
    }

    {:reply, simple_status, state}
  end

  @impl true
  def handle_call(:get_detailed_status, _from, state) do
    detailed_status = %{
      api_status: state.api_status,
      last_check: state.last_check,
      last_success: state.last_success,
      response_time: state.response_time,
      error_count: state.error_count,
      success_count: state.success_count,
      total_checks: state.total_checks,
      uptime_percentage: state.uptime_percentage,
      last_error: state.last_error,
      endpoints_status: state.endpoints_status,
      api_base_url: @api_base_url
    }

    {:reply, detailed_status, state}
  end

  @impl true
  def handle_cast(:check_now, state) do
    new_state = perform_health_check(state)
    {:noreply, new_state}
  end

  ## Funções Privadas

  defp perform_health_check(state) do
    start_time = System.monotonic_time(:millisecond)

    # Verifica múltiplos endpoints
    endpoints_to_check = [
      {"/dashboard/sale", "Dashboard Sale API"},
      {"/dashboard/sale/company", "Company Data API"}
    ]

    endpoints_results = check_endpoints(endpoints_to_check)
    end_time = System.monotonic_time(:millisecond)
    response_time = end_time - start_time

    # Determina status geral
    overall_status = determine_overall_status(endpoints_results)
    is_success = overall_status == :healthy

    # Atualiza contadores
    new_total_checks = state.total_checks + 1
    new_error_count = if is_success, do: 0, else: state.error_count + 1
    new_success_count = if is_success, do: state.success_count + 1, else: state.success_count

    # Calcula uptime (baseado nas últimas verificações)
    new_uptime = calculate_uptime_percentage(new_success_count, new_total_checks)

    # Determina último erro
    last_error = if is_success do
      nil
    else
      extract_error_from_results(endpoints_results)
    end

    updated_state = %{state |
      api_status: overall_status,
      last_check: DateTime.utc_now(),
      last_success: if(is_success, do: DateTime.utc_now(), else: state.last_success),
      response_time: response_time,
      error_count: new_error_count,
      success_count: new_success_count,
      total_checks: new_total_checks,
      uptime_percentage: new_uptime,
      last_error: last_error,
      endpoints_status: endpoints_results
    }

    # Log do resultado
    log_health_check_result(updated_state, is_success)

    updated_state
  end

  defp check_endpoints(endpoints) do
    endpoints
    |> Enum.map(fn {path, name} -> {path, name, check_single_endpoint(path)} end)
    |> Enum.into(%{}, fn {path, name, result} ->
      {path, %{name: name, status: elem(result, 0), details: elem(result, 1)}}
    end)
  end

  defp check_single_endpoint(path) do
    url = @api_base_url <> path

    case HTTPoison.get(url, [], timeout: @timeout, recv_timeout: @timeout) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        {:healthy, "OK"}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:unhealthy, "HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        {:unhealthy, "Timeout"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:unhealthy, "Connection error: #{reason}"}

      error ->
        {:unhealthy, "Unknown error: #{inspect(error)}"}
    end
  end

  defp determine_overall_status(endpoints_results) do
    statuses = endpoints_results |> Map.values() |> Enum.map(& &1.status)

    cond do
      Enum.all?(statuses, & &1 == :healthy) -> :healthy
      Enum.any?(statuses, & &1 == :healthy) -> :degraded
      true -> :unhealthy
    end
  end

  defp calculate_uptime_percentage(success_count, total_checks) when total_checks > 0 do
    (success_count / total_checks * 100) |> Float.round(2)
  end
  defp calculate_uptime_percentage(_, _), do: 0.0

  defp extract_error_from_results(endpoints_results) do
    endpoints_results
    |> Map.values()
    |> Enum.find(& &1.status != :healthy)
    |> case do
      nil -> nil
      endpoint -> "#{endpoint.name}: #{endpoint.details}"
    end
  end

  defp schedule_next_check do
    Process.send_after(self(), :perform_check, @check_interval)
  end

  defp log_health_check_result(state, is_success) do
    if is_success do
      Logger.debug("Health check passed - Response time: #{state.response_time}ms, Uptime: #{state.uptime_percentage}%")
    else
      Logger.warning("Health check failed - Error: #{state.last_error}, Consecutive failures: #{state.error_count}")
    end
  end

  defp format_status_for_broadcast(state) do
    %{
      status: state.api_status,
      uptime: state.uptime_percentage,
      response_time: state.response_time,
      last_check: state.last_check,
      error_count: state.error_count
    }
  end
end
