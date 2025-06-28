defmodule JuruConnect.Config.SupervisorSyncSetup do
  @moduledoc """
  Configuração e setup para sincronização de dados de supervisores.

  Este módulo fornece instruções e exemplos de como configurar o Oban
  e HTTPoison para a coleta periódica de dados da API.
  """

  @doc """
  Dependências necessárias no mix.exs:

      defp deps do
        [
          {:oban, "~> 2.15"},
          {:httpoison, "~> 1.8"},
          {:jason, "~> 1.4"},
          # ... outras dependências
        ]
      end
  """
  def required_dependencies, do: [:oban, :httpoison, :jason]

  @doc """
  Configuração do Oban no config/config.exs:

      config :juru_connect, Oban,
        repo: JuruConnect.Repo,
        plugins: [
          Oban.Plugins.Pruner,
          {Oban.Plugins.Cron,
           crontab: [
             # Coleta dados a cada 2 horas
             {"0 */2 * * *", JuruConnect.Workers.SupervisorDataWorker,
              %{"api_url" => "https://sua-api.com/supervisores"}},
           ]}
        ],
        queues: [
          default: 10,
          api_sync: 5
        ]
  """
  def oban_config_example do
    """
    config :juru_connect, Oban,
      repo: JuruConnect.Repo,
      plugins: [
        Oban.Plugins.Pruner,
        {Oban.Plugins.Cron,
         crontab: [
           {"0 */2 * * *", JuruConnect.Workers.SupervisorDataWorker,
            %{"api_url" => "https://sua-api.com/supervisores"}}
         ]}
      ],
      queues: [
        default: 10,
        api_sync: 5
      ]
    """
  end

  @doc """
  Adicione o Oban ao application.ex:

      def start(_type, _args) do
        children = [
          JuruConnect.Repo,
          {Oban, Application.fetch_env!(:juru_connect, Oban)},
          JuruConnectWeb.Endpoint
        ]

        opts = [strategy: :one_for_one, name: JuruConnect.Supervisor]
        Supervisor.start_link(children, opts)
      end
  """
  def application_setup_example do
    """
    # Em lib/juru_connect/application.ex

    def start(_type, _args) do
      children = [
        JuruConnect.Repo,
        {Oban, Application.fetch_env!(:juru_connect, Oban)},
        JuruConnectWeb.Endpoint
      ]

      opts = [strategy: :one_for_one, name: JuruConnect.Supervisor]
      Supervisor.start_link(children, opts)
    end
    """
  end

  @doc """
  Exemplo de uso manual (sem Oban) para testes:

      # Executar no IEx
      api_url = "https://sua-api.com/supervisores"

      case HTTPoison.get(api_url) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, data} = Jason.decode(body)
          JuruConnect.Sales.create_supervisor_data_from_api(data)
        {:error, reason} ->
          IO.inspect(reason, label: "Erro na requisição")
      end
  """
  def manual_sync_example do
    quote do
      api_url = "https://sua-api.com/supervisores"

      case HTTPoison.get(api_url) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} ->
              JuruConnect.Sales.create_supervisor_data_from_api(data)
            {:error, decode_error} ->
              {:error, {:json_decode_error, decode_error}}
          end
        {:error, reason} ->
          {:error, {:http_request_error, reason}}
      end
    end
  end

  @doc """
  Agendamento manual de job (após configurar Oban):

      # Executar uma vez
      %{"api_url" => "https://sua-api.com/supervisores"}
      |> JuruConnect.Workers.SupervisorDataWorker.new()
      |> Oban.insert()

      # Agendar para daqui 1 hora
      %{"api_url" => "https://sua-api.com/supervisores"}
      |> JuruConnect.Workers.SupervisorDataWorker.new(in: 3600)
      |> Oban.insert()
  """
  def manual_scheduling_examples do
    [
      immediate: quote do
        %{"api_url" => "https://sua-api.com/supervisores"}
        |> JuruConnect.Workers.SupervisorDataWorker.new()
        |> Oban.insert()
      end,

      scheduled: quote do
        %{"api_url" => "https://sua-api.com/supervisores"}
        |> JuruConnect.Workers.SupervisorDataWorker.new(in: 3600)
        |> Oban.insert()
      end
    ]
  end
end
