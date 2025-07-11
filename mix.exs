defmodule App.MixProject do
  use Mix.Project

  def project do
    [
      app: :app,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Documentação
      name: "JuruConnect",
      description: "Sistema de gestão comercial para Jurunense Home Center",
      source_url: "https://github.com/jurunense/juruconnect",
      homepage_url: "https://juruconnect.com.br",
      docs: docs(),
      package: package()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {App.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.21"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:sweet_xml, "~> 0.6"},
      {:comeonin, "~> 5.3"},
      {:argon2_elixir, "~> 3.0"},
      {:pbkdf2_elixir, "~> 2.0"},
      {:live_debugger, "~> 0.3", only: [:dev]},
      {:fuse, "~> 2.5.0"},
      {:uuid, "~> 1.1"},
      {:swoosh, "~> 1.5"},
      {:plug_cowboy, "~> 2.5"},
      {:cors_plug, "~> 3.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_aws, "~> 2.4"},
      {:ex_aws_s3, "~> 2.3"},
      {:hackney, "~> 1.9"},
      {:finch, "~> 0.13"},
      {:httpoison, "~> 2.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:igniter, "~> 0.5.40", only: :dev, runtime: false},
      {:oban, "~> 2.17"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.2"},
      {:bcrypt_elixir, "~> 3.0"},
      {:timex, "~> 3.7"},
      {:tzdata, "~> 1.1"},

      # Documentação
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end

  # Configuração da documentação
  defp docs do
    [
      # Página principal
      main: "readme",

      # Arquivos extras para incluir
      extras: [
        "README.md",
        "CHANGELOG.md": [title: "Changelog"],
        "docs/getting-started.md": [title: "Começando"],
        "docs/api-guide.md": [title: "Guia da API"],
        "docs/authentication.md": [title: "Autenticação"],
        "docs/deployment.md": [title: "Deploy"]
      ],

      # Grupos de módulos
      groups_for_modules: [
        "Core": [
          App.Application,
          App.Repo
        ],
        "Contexts": [
          App.Accounts,
          App.Auth,
          App.Chat,
          App.Dashboard,
          App.Sales
        ],
        "Authentication": [
          App.Auth.Manager,
          App.Auth.RateLimiter,
          App.Auth.SecurityLogger,
          App.Auth.PasswordPolicy,
          App.Auth.PasswordReset
        ],
        "Web Layer": [
          AppWeb,
          AppWeb.Endpoint,
          AppWeb.Router
        ],
        "Live Views": [
          AppWeb.DashboardResumoLive,
          AppWeb.AuthLive.Login,
          AppWeb.AdminLive.SecurityDashboard,
          AppWeb.ObanMonitorLive
        ],
        "Components": [
          AppWeb.CoreComponents,
          AppWeb.DashboardComponents
        ],
        "Controllers": [
          AppWeb.SessionController,
          AppWeb.ErrorController
        ],
        "Auth Plugs": [
          AppWeb.Auth.Guardian,
          AppWeb.Auth.GuardianPlug,
          AppWeb.Auth.GuardianSessionPlug,
          AppWeb.Auth.GuardianErrorHandler
        ],
        "Background Jobs": [
          JuruConnect.Workers,
          JuruConnect.Api
        ],
        "Schemas": [
          App.Accounts.User,
          App.Chat.Message,
          App.Schemas
        ]
      ],

      # Filtros
      filter_modules: fn module, _metadata ->
        # Incluir apenas módulos do projeto
        module
        |> Atom.to_string()
        |> String.starts_with?(["App", "AppWeb", "JuruConnect"])
      end,

      # Formatação
      source_ref: "main",
      formatters: ["html"]
    ]
  end

  # Informações do pacote
  defp package do
    [
      description: "Sistema de gestão comercial para Jurunense Home Center",
      files: ~w(lib priv .formatter.exs mix.exs README* CHANGELOG*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/jurunense/juruconnect",
        "Docs" => "https://docs.juruconnect.com.br"
      }
    ]
  end
end
