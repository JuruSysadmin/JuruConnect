defmodule App.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AppWeb.Telemetry,
      App.Repo,
      {DNSCluster, query: Application.get_env(:app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: App.PubSub},
      {Registry, keys: :unique, name: App.ChatRegistry},
      {AppWeb.Presence, []},
      # Start the Finch HTTP client for sending emails
      {Finch, name: App.Finch},
      # Oban for background jobs
      {Oban, Application.fetch_env!(:app, Oban)},
      # DashboardDataServer centraliza o fetch da API
      App.DashboardDataServer,
      # Start a worker by calling: App.Worker.start_link(arg)
      # {App.Worker, arg},
      # Start to serve requests, typically the last entry
      AppWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: App.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
