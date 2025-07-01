defmodule AppWeb.Presence do
  @moduledoc """
  Provides presence tracking across channels and processes.
  """
  use Phoenix.Presence,
    otp_app: :app,
    pubsub_server: App.PubSub
end
