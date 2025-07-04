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
      # Chat system supervisors
      {App.Chat.RateLimiter, []},
      {App.Chat.MessageStatus, []},
      {App.Chat.Notifications, []},
      # Start the Finch HTTP client for sending emails
      {Finch, name: App.Finch},
      # Oban for background jobs
      {Oban, Application.fetch_env!(:app, Oban)},
      # Nova arquitetura do Dashboard (separação de responsabilidades)
      App.Dashboard.Supervisor,
      # Mantém o antigo para compatibilidade (será removido depois)
      App.DashboardDataServer,
      # CelebrationManager gerencia celebrações com cache
      App.CelebrationManager,
      # RateLimiter cleanup process para limpeza automática
      App.Auth.RateLimiterCleanup,
      # Password Reset system para recuperação segura
      App.Auth.PasswordReset,
      # Health Check system para monitoramento da API externa
      App.HealthCheck,
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
