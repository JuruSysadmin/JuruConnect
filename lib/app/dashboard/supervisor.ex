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
        get_pid_status(pid)
      {^child_id, :restarting, _type, _modules} ->
        {:ok, :restarting, nil}
      {^child_id, :undefined, _type, _modules} ->
        {:ok, :not_started, nil}
      nil ->
        {:error, :not_found}
    end
  end

  defp get_pid_status(pid) when is_pid(pid) do
    case Process.alive?(pid) do
      true -> {:ok, :running, pid}
      false -> {:ok, :not_running, nil}
    end
  end

  def health_check do
    children = which_children()

    health_status =
      Enum.map(children, fn {id, pid, _type, _modules} ->
        status = get_child_health_status(pid)
        {id, status}
      end)

    all_healthy = Enum.all?(health_status, fn {_id, status} -> status == :healthy end)

    %{
      overall_status: get_overall_status(all_healthy),
      children: health_status,
      timestamp: DateTime.utc_now()
    }
  end

  defp get_child_health_status(pid) when is_pid(pid) do
    case Process.alive?(pid) do
      true -> :healthy
      false -> :unhealthy
    end
  end

  defp get_child_health_status(_), do: :unhealthy

  defp get_overall_status(true), do: :healthy
  defp get_overall_status(false), do: :unhealthy
end
