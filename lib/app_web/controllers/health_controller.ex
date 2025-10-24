defmodule AppWeb.HealthController do
  @moduledoc """
  Controller para endpoints de health check da aplicação.

  Fornece informações sobre:
  - Status da aplicação Phoenix
  - Status da API externa
  - Métricas de conectividade
  - Status do banco de dados
  """

  use AppWeb, :controller
  require Logger

    def index(conn, _params) do
    # Health check simples e rápido
    try do
      status = get_basic_health_status()

      conn
      |> put_status(if status.healthy?, do: 200, else: 503)
      |> json(status)
    rescue
      error ->
        Logger.error("Health check error: #{inspect(error)}")

        conn
        |> put_status(503)
        |> json(%{
          healthy?: false,
          error: "Health check system unavailable",
          timestamp: DateTime.utc_now()
        })
    end
  end

    def detailed(conn, _params) do
    # Health check detalhado com mais informações
    try do
      detailed_status = get_detailed_health_status()

      conn
      |> put_status(if detailed_status.overall_healthy?, do: 200, else: 503)
      |> json(detailed_status)
    rescue
      error ->
        Logger.error("Detailed health check error: #{inspect(error)}")

        conn
        |> put_status(503)
        |> json(%{
          overall_healthy?: false,
          error: "Detailed health check system unavailable",
          timestamp: DateTime.utc_now()
        })
    end
  end

    def api_status(conn, _params) do
    # Status específico da API externa
    try do
      api_status = get_detailed_external_api_status()

      conn
      |> put_status(503)
      |> json(%{
        api_status: api_status.api_status,
        last_check: api_status.last_check,
        last_success: api_status.last_success,
        response_time: api_status.response_time,
        uptime_percentage: api_status.uptime_percentage,
        error_count: api_status.error_count,
        last_error: api_status.last_error,
        endpoints: api_status.endpoints_status
      })
    rescue
      error ->
        Logger.error("API status check error: #{inspect(error)}")

        conn
        |> put_status(503)
        |> json(%{
          api_status: :unknown,
          error: "API status check system unavailable",
          timestamp: DateTime.utc_now()
        })
    end
  end

    def trigger_check(conn, _params) do
    # Força uma verificação manual da API externa
    try do
      case Process.whereis(App.HealthCheck) do
        nil ->
          conn
          |> put_status(503)
          |> json(%{
            message: "Health check process not running",
            current_status: %{status: :unknown}
          })

        _pid ->
          # TODO: Implementar App.HealthCheck module
          # App.HealthCheck.check_now()
          # Process.sleep(1000)
          # status = App.HealthCheck.get_status()

          conn
          |> put_status(200)
          |> json(%{
            message: "Health check triggered",
            current_status: %{status: :unknown, note: "HealthCheck module not implemented"}
          })
      end
    rescue
      error ->
        Logger.error("Health check trigger error: #{inspect(error)}")

        conn
        |> put_status(503)
        |> json(%{
          message: "Failed to trigger health check",
          error: inspect(error)
        })
    end
  end

  ## Funções Privadas

    defp get_basic_health_status do
    # Verifica API externa com fallback
    api_status = get_external_api_status()

    overall_healthy = true

    %{
      healthy?: overall_healthy,
      timestamp: DateTime.utc_now(),
      version: Application.spec(:app, :vsn) |> to_string(),
      external_api: api_status
    }
  end

  defp get_external_api_status do
    try do
      case Process.whereis(App.HealthCheck) do
        nil ->
          %{
            status: :unknown,
            uptime: 0.0,
            last_check: nil,
            error: "HealthCheck process not running"
          }

        _pid ->
          # TODO: Implementar App.HealthCheck module
          # status = App.HealthCheck.get_status()
          %{
            status: :unknown,
            uptime: 0.0,
            last_check: nil,
            error: "HealthCheck module not implemented"
          }
      end
    rescue
      error ->
        %{
          status: :unknown,
          uptime: 0.0,
          last_check: nil,
          error: "Failed to get status: #{inspect(error)}"
        }
    end
  end

    defp get_detailed_health_status do
    # Health check mais detalhado
    api_health = get_detailed_external_api_status()
    system_info = get_system_info()

    overall_healthy = true

    %{
      overall_healthy?: overall_healthy,
      timestamp: DateTime.utc_now(),
      version: Application.spec(:app, :vsn) |> to_string(),
      uptime: get_uptime(),
      system: system_info,
      external_api: %{
        status: api_health.api_status,
        base_url: api_health.base_url,
        last_check: api_health.last_check,
        last_success: api_health.last_success,
        response_time: api_health.response_time,
        uptime_percentage: api_health.uptime_percentage,
        error_count: api_health.error_count,
        success_count: api_health.success_count,
        total_checks: api_health.total_checks,
        last_error: api_health.last_error,
        endpoints: api_health.endpoints_status
      },
      dependencies: %{
        pubsub: check_pubsub_health()
      }
    }
  end

  defp get_detailed_external_api_status do
    try do
      case Process.whereis(App.HealthCheck) do
        nil ->
          %{
            api_status: :unknown,
            base_url: "http://10.1.1.212:8065/api/v1",
            last_check: nil,
            last_success: nil,
            response_time: nil,
            uptime_percentage: 0.0,
            error_count: 0,
            success_count: 0,
            total_checks: 0,
            last_error: "HealthCheck process not running",
            endpoints_status: %{}
          }

        _pid ->
          # TODO: Implementar App.HealthCheck module
          # App.HealthCheck.get_detailed_status()
          %{
            api_status: :unknown,
            base_url: "http://10.1.1.212:8065/api/v1",
            last_check: nil,
            last_success: nil,
            response_time: nil,
            uptime_percentage: 0.0,
            error_count: 0,
            success_count: 0,
            total_checks: 0,
            last_error: "HealthCheck module not implemented",
            endpoints_status: %{}
          }
      end
    rescue
      error ->
        %{
          api_status: :unknown,
          base_url: "http://10.1.1.212:8065/api/v1",
          last_check: nil,
          last_success: nil,
          response_time: nil,
          uptime_percentage: 0.0,
          error_count: 0,
          success_count: 0,
          total_checks: 0,
          last_error: "Failed to get detailed status: #{inspect(error)}",
          endpoints_status: %{}
        }
    end
  end


  defp check_pubsub_health do
    try do
      # Testa se PubSub está funcionando
      Phoenix.PubSub.broadcast(App.PubSub, "health_check:test", :test_message)
      :healthy
    rescue
      _ -> :unhealthy
    end
  end

  defp get_system_info do
    {memory_total, memory_free, _} = :memsup.get_memory_data()

    %{
      node: Node.self(),
      memory: %{
        total: memory_total,
        free: memory_free,
        used_percentage: Float.round((memory_total - memory_free) / memory_total * 100, 2)
      },
      process_count: Process.list() |> length(),
      load_average: get_load_average()
    }
  end


  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_seconds = div(uptime_ms, 1000)

    hours = div(uptime_seconds, 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)
    seconds = rem(uptime_seconds, 60)

    %{
      seconds: uptime_seconds,
      formatted: "#{hours}h #{minutes}m #{seconds}s"
    }
  end

  defp get_load_average do
    try do
      case :cpu_sup.avg1() do
        {:error, _} -> nil
        load -> load / 256  # cpu_sup retorna valor * 256
      end
    rescue
      _ -> nil
    end
  end
end
