defmodule App.Dashboard.Supervisor do
  @moduledoc """
  Supervisor para todos os processos relacionados ao dashboard.
  Organiza a árvore de supervisão seguindo as melhores práticas:
  - DataStore (estado crítico) - reinicia sempre
  - CacheManager (cache pode ser perdido) - reinicia transiente
  - EventBroadcaster (eventos) - reinicia sempre
  - DataFetcher (busca dados) - reinicia transiente
  - Orchestrator (coordenação) - reinicia sempre
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    children = [
      {App.Dashboard.DataStore, []},
      {App.Dashboard.CacheManager, []},
      {App.Dashboard.EventBroadcaster, []},
      {App.Dashboard.DataFetcher, []},
      {App.Dashboard.Orchestrator, []},
      {App.Dashboard.SupervisorMonitor, []},
      {App.Returns.ReturnsMonitor, []}
    ]

    opts = [
      strategy: :rest_for_one,
      name: App.Dashboard.Supervisor,
      max_restarts: 3,
      max_seconds: 60
    ]

    Logger.info("Dashboard Supervisor starting with #{length(children)} children")
    Supervisor.init(children, opts)
  end

  def which_children do
    Supervisor.which_children(__MODULE__)
  end

  def count_children do
    Supervisor.count_children(__MODULE__)
  end

  def restart_child(child_id) do
    case Supervisor.terminate_child(__MODULE__, child_id) do
      :ok ->
        Supervisor.restart_child(__MODULE__, child_id)
      error ->
        error
    end
  end

  def get_child_status(child_id) do
    children = which_children()
    case List.keyfind(children, child_id, 0) do
      {^child_id, pid, _type, _modules} when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, :running, pid}
        else
          {:ok, :not_running, nil}
        end
      {^child_id, :restarting, _type, _modules} ->
        {:ok, :restarting, nil}
      {^child_id, :undefined, _type, _modules} ->
        {:ok, :not_started, nil}
      nil ->
        {:error, :not_found}
    end
  end

  def health_check do
    children = which_children()

    health_status =
      Enum.map(children, fn {id, pid, _type, _modules} ->
        status = if is_pid(pid) and Process.alive?(pid) do
          :healthy
        else
          :unhealthy
        end

        {id, status}
      end)

    all_healthy = Enum.all?(health_status, fn {_id, status} -> status == :healthy end)

    %{
      overall_status: if(all_healthy, do: :healthy, else: :unhealthy),
      children: health_status,
      timestamp: DateTime.utc_now()
    }
  end
end
