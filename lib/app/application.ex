defmodule App.Application do
  @moduledoc """
  Main application supervisor that manages all system processes.

  Coordinates the startup of core services including database, pubsub,
  chat registry, and web endpoint in the correct dependency order.
  """

  use Application

  @impl true
  def start(_type, _args) do
    supervisor_children = build_supervisor_children()
    supervisor_options = build_supervisor_options()

    Supervisor.start_link(supervisor_children, supervisor_options)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Builds the list of child processes in dependency order
  defp build_supervisor_children do
    [
      AppWeb.Telemetry,
      App.Repo,
      build_dns_cluster(),
      {Phoenix.PubSub, name: App.PubSub},
      {Registry, keys: :unique, name: App.ChatRegistry},
      {AppWeb.Presence, []},
      {Finch, name: App.Finch},
      AppWeb.Endpoint
    ]
  end

  # Configures DNS cluster for service discovery in production
  defp build_dns_cluster do
    dns_query = Application.get_env(:app, :dns_cluster_query) || :ignore
    {DNSCluster, query: dns_query}
  end

  # Supervisor configuration for fault tolerance
  defp build_supervisor_options do
    [strategy: :one_for_one, name: App.Supervisor]
  end
end
