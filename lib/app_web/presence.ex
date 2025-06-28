defmodule AppWeb.Presence do
  @moduledoc """
  Módulo de presença para tracking de usuários online em tempo real.
  """
  use Phoenix.Presence,
    otp_app: :app,
    pubsub_server: App.PubSub
end
