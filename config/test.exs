import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :app, App.Repo,
  username: "postgres",
  password: "password",
  hostname: "localhost",
  port: 5433,
  database: "chat_app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :app, AppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "jFpSz0RgsEUAO92TDA/5NiHmkrOR4zrSjSe79fvlCfk/PBSRGbsedbFHLwE9xRUV",
  server: false

# Configure Guardian for testing
config :app, AppWeb.Auth.Guardian,
  issuer: "app_web",
  secret_key: "gI8MZ1hy5sB6LnbmV2sbu3IiINqYTPdU8FLFz+bb+3/w9XVza+1adCtIWak1CuHg"

# In test we don't send emails
config :app, App.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :ex_aws,
  access_key_id: "minio",
  secret_access_key: "minio123",
  region: "us-east-1"

config :ex_aws, :s3,
  scheme: "http://",
  host: "localhost",
  port: 9000,
  region: "us-east-1"
