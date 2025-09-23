defmodule App.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc """
Supervisor principal da aplicação JuruConnect.

Este módulo inicializa e supervisiona todos os serviços essenciais do sistema, incluindo:
- Repositório Ecto (App.Repo)
- Telemetria (AppWeb.Telemetry)
- Sistema PubSub (Phoenix.PubSub)
- Servidor de dados do dashboard (App.DashboardDataServer)
- Gerenciador de celebrações (App.CelebrationManager)
- Endpoint HTTP/HTTPS (AppWeb.Endpoint)
- Gerenciador de jobs em background (Oban)

Segue o padrão OTP supervisionando os processos críticos para garantir alta disponibilidade e resiliência. Utiliza a estratégia `:one_for_one`, reiniciando apenas o processo que falhar.

Responsável também por aplicar mudanças de configuração dinâmica no endpoint durante atualizações.
"""

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      App.Repo,
      # Start the Telemetry supervisor
      AppWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: App.PubSub},
      # Start Presence para rastreamento de usuários online
      AppWeb.Presence,
      # Start the DashboardDataServer para dados do dashboard
      App.DashboardDataServer,
      # Start the CelebrationManager para controle de celebrações
      App.CelebrationManager,
      # Start the Endpoint (http/https)
      AppWeb.Endpoint,
      # Start Oban for background jobs
      {Oban, oban_config()}
      # Start a worker by calling: App.Worker.start_link(arg)
      # {App.Worker, arg}
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

  defp oban_config do
    Application.fetch_env!(:app, Oban)
  end
end
