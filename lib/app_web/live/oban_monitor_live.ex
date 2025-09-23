defmodule AppWeb.ObanMonitorLive do
  @moduledoc """
  LiveView personalizada para monitoramento do Oban.

  Fornece interface web para visualizar filas, jobs e estatísticas
  do Oban em tempo real.
  """

  use AppWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    socket = if connected?(socket) do
      # Atualiza a cada 5 segundos
      :timer.send_interval(5000, self(), :refresh)
      socket
    else
      socket
    end

    socket =
      socket
      |> assign(:page_title, "Monitor Oban")
      |> assign(:queues, get_queue_stats())
      |> assign(:recent_jobs, get_recent_jobs())
      |> assign(:stats, get_oban_stats())
      |> assign(:last_update, DateTime.utc_now())

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    socket =
      socket
      |> assign(:queues, get_queue_stats())
      |> assign(:recent_jobs, get_recent_jobs())
      |> assign(:stats, get_oban_stats())
      |> assign(:last_update, DateTime.utc_now())

    {:noreply, socket}
  end

  @impl true
  def handle_event("pause_queue", %{"queue" => queue}, socket) do
    case String.to_existing_atom(queue) do
      queue_name when is_atom(queue_name) ->
        case Oban.pause_queue(queue: queue_name) do
          :ok ->
            {:noreply, put_flash(socket, :info, "Fila #{queue} pausada com sucesso")}
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Erro ao pausar fila: #{inspect(reason)}")}
        end
      _ ->
        {:noreply, put_flash(socket, :error, "Nome de fila inválido: #{queue}")}
    end
  rescue
    ArgumentError ->
      {:noreply, put_flash(socket, :error, "Nome de fila inválido: #{queue}")}
  end

  @impl true
  def handle_event("resume_queue", %{"queue" => queue}, socket) do
    case String.to_existing_atom(queue) do
      queue_name when is_atom(queue_name) ->
        case Oban.resume_queue(queue: queue_name) do
          :ok ->
            {:noreply, put_flash(socket, :info, "Fila #{queue} reativada com sucesso")}
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Erro ao reativar fila: #{inspect(reason)}")}
        end
      _ ->
        {:noreply, put_flash(socket, :error, "Nome de fila inválido: #{queue}")}
    end
  rescue
    ArgumentError ->
      {:noreply, put_flash(socket, :error, "Nome de fila inválido: #{queue}")}
  end

  @impl true
  def handle_event("create_test_job", _params, socket) do
    # Note: JuruConnect.Workers.SupervisorDataWorker is not defined
    # This functionality needs to be implemented
    {:noreply, put_flash(socket, :error, "Worker não implementado")}
  end

    @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 font-mono">
      <div class="max-w-7xl mx-auto px-4 py-8">
        <!-- Header -->
        <div class="flex justify-between items-center mb-8">
          <div>
            <h1 class="text-2xl font-normal text-gray-900">Monitor Oban</h1>
            <p class="text-sm text-gray-600 mt-1">Sistema de monitoramento de jobs</p>
          </div>
          <div class="text-xs text-gray-500 font-mono">
            <%= @last_update |> Calendar.strftime("%H:%M:%S") %>
          </div>
        </div>

        <!-- Estatísticas -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
          <div class="bg-white border border-gray-200 p-4">
            <div class="text-xs text-gray-600 mb-1">TOTAL</div>
            <div class="text-2xl font-mono text-gray-900"><%= @stats.total_jobs %></div>
          </div>

          <div class="bg-white border border-gray-200 p-4">
            <div class="text-xs text-gray-600 mb-1">DISPONÍVEIS</div>
            <div class="text-2xl font-mono text-gray-900"><%= @stats.available_jobs %></div>
          </div>

          <div class="bg-white border border-gray-200 p-4">
            <div class="text-xs text-gray-600 mb-1">EXECUTANDO</div>
            <div class="text-2xl font-mono text-gray-900"><%= @stats.executing_jobs %></div>
          </div>

          <div class="bg-white border border-gray-200 p-4">
            <div class="text-xs text-gray-600 mb-1">FALHARAM</div>
            <div class="text-2xl font-mono text-gray-900"><%= @stats.failed_jobs %></div>
          </div>
        </div>

        <!-- Controles -->
        <div class="mb-8">
          <button
            phx-click="create_test_job"
            class="bg-gray-900 hover:bg-gray-700 text-white text-sm px-4 py-2 font-mono transition-colors"
          >
            Criar Job de Teste
          </button>
        </div>

        <!-- Filas -->
        <div class="bg-white border border-gray-200 mb-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-sm font-normal text-gray-900">Filas</h2>
          </div>

          <div class="overflow-x-auto">
            <table class="min-w-full">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs text-gray-600 font-mono">FILA</th>
                  <th class="px-6 py-3 text-left text-xs text-gray-600 font-mono">STATUS</th>
                  <th class="px-6 py-3 text-left text-xs text-gray-600 font-mono">JOBS</th>
                  <th class="px-6 py-3 text-left text-xs text-gray-600 font-mono">WORKERS</th>
                  <th class="px-6 py-3 text-left text-xs text-gray-600 font-mono">AÇÕES</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200">
                <%= for queue <- @queues do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 text-sm font-mono text-gray-900">
                      <%= queue.name %>
                    </td>
                    <td class="px-6 py-4">
                      <span class={[
                        "text-xs font-mono px-2 py-1",
                        if(queue.paused, do: "text-red-700 bg-red-50", else: "text-green-700 bg-green-50")
                      ]}>
                        <%= if queue.paused, do: "PAUSADA", else: "ATIVA" %>
                      </span>
                    </td>
                    <td class="px-6 py-4 text-sm font-mono text-gray-900">
                      <%= queue.available_count %>
                    </td>
                    <td class="px-6 py-4 text-sm font-mono text-gray-900">
                      <%= queue.limit %>
                    </td>
                    <td class="px-6 py-4">
                      <%= if queue.paused do %>
                        <button
                          phx-click="resume_queue"
                          phx-value-queue={queue.name}
                          class="text-xs font-mono text-green-700 hover:text-green-900 underline"
                        >
                          reativar
                        </button>
                      <% else %>
                        <button
                          phx-click="pause_queue"
                          phx-value-queue={queue.name}
                          class="text-xs font-mono text-red-700 hover:text-red-900 underline"
                        >
                          pausar
                        </button>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Jobs Recentes -->
        <div class="bg-white border border-gray-200">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-sm font-normal text-gray-900">Jobs Recentes</h2>
          </div>

          <div class="overflow-x-auto">
            <table class="min-w-full">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs text-gray-600 font-mono">ID</th>
                  <th class="px-6 py-3 text-left text-xs text-gray-600 font-mono">WORKER</th>
                  <th class="px-6 py-3 text-left text-xs text-gray-600 font-mono">FILA</th>
                  <th class="px-6 py-3 text-left text-xs text-gray-600 font-mono">ESTADO</th>
                  <th class="px-6 py-3 text-left text-xs text-gray-600 font-mono">AGENDADO</th>
                  <th class="px-6 py-3 text-left text-xs text-gray-600 font-mono">TENTATIVAS</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200">
                <%= for job <- @recent_jobs do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 text-sm font-mono text-gray-900">
                      <%= job.id %>
                    </td>
                    <td class="px-6 py-4 text-sm font-mono text-gray-900">
                      <%= job.worker |> String.split(".") |> List.last() %>
                    </td>
                    <td class="px-6 py-4 text-sm font-mono text-gray-900">
                      <%= job.queue %>
                    </td>
                    <td class="px-6 py-4">
                      <span class={[
                        "text-xs font-mono px-2 py-1",
                        case job.state do
                          "available" -> "text-blue-700 bg-blue-50"
                          "executing" -> "text-yellow-700 bg-yellow-50"
                          "completed" -> "text-green-700 bg-green-50"
                          "retryable" -> "text-orange-700 bg-orange-50"
                          "cancelled" -> "text-gray-700 bg-gray-50"
                          "discarded" -> "text-red-700 bg-red-50"
                          _ -> "text-gray-700 bg-gray-50"
                        end
                      ]}>
                        <%= String.upcase(job.state) %>
                      </span>
                    </td>
                    <td class="px-6 py-4 text-sm font-mono text-gray-900">
                      <%= if job.scheduled_at do %>
                        <%= job.scheduled_at |> Calendar.strftime("%H:%M:%S") %>
                      <% else %>
                        agora
                      <% end %>
                    </td>
                    <td class="px-6 py-4 text-sm font-mono text-gray-900">
                      <%= job.attempt %>/<%= job.max_attempts %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

    defp get_queue_stats do
    config = Application.get_env(:app, Oban, [])
    queues = Keyword.get(config, :queues, [])

    Enum.map(queues, fn {queue_name, limit} ->
      available_count =
        try do
          # Consulta direta ao banco para contar jobs disponíveis
          query = """
          SELECT COUNT(*)
          FROM oban_jobs
          WHERE queue = $1 AND state = 'available'
          """
          case App.Repo.query(query, [to_string(queue_name)]) do
            {:ok, %{rows: [[count]]}} -> count
            _ -> 0
          end
        rescue
          _ -> 0
        end

      paused =
        try do
          # Verificar se a fila está pausada usando check_queue
          case Oban.check_queue(queue: queue_name) do
            %{paused: paused} -> paused
            _ -> false
          end
        rescue
          _ -> false
        end

      %{
        name: queue_name,
        limit: limit,
        available_count: available_count,
        paused: paused
      }
    end)
  end

  defp get_recent_jobs do
    try do
      # Busca jobs recentes de todas as filas
      from_time = DateTime.utc_now() |> DateTime.add(-3600, :second) # Última hora

      query = """
      SELECT id, worker, queue, state, scheduled_at, attempt, max_attempts, inserted_at
      FROM oban_jobs
      WHERE inserted_at >= $1
      ORDER BY inserted_at DESC
      LIMIT 20
      """

      case App.Repo.query(query, [from_time]) do
        {:ok, %{rows: rows}} ->
          Enum.map(rows, fn [id, worker, queue, state, scheduled_at, attempt, max_attempts, _inserted_at] ->
            %{
              id: id,
              worker: worker,
              queue: queue,
              state: state,
              scheduled_at: scheduled_at,
              attempt: attempt,
              max_attempts: max_attempts
            }
          end)
        _ ->
          []
      end
    rescue
      _ -> []
    end
  end

  defp get_oban_stats do
    try do
      query = """
      SELECT
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE state = 'available') as available,
        COUNT(*) FILTER (WHERE state = 'executing') as executing,
        COUNT(*) FILTER (WHERE state IN ('retryable', 'discarded')) as failed
      FROM oban_jobs
      WHERE inserted_at >= NOW() - INTERVAL '24 hours'
      """

      case App.Repo.query(query, []) do
        {:ok, %{rows: [[total, available, executing, failed]]}} ->
          %{
            total_jobs: total || 0,
            available_jobs: available || 0,
            executing_jobs: executing || 0,
            failed_jobs: failed || 0
          }
        _ ->
          %{total_jobs: 0, available_jobs: 0, executing_jobs: 0, failed_jobs: 0}
      end
    rescue
      _ ->
        %{total_jobs: 0, available_jobs: 0, executing_jobs: 0, failed_jobs: 0}
    end
  end
end
