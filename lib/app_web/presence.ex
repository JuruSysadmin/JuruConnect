defmodule AppWeb.Presence do
  @moduledoc """
  Phoenix Presence module for tracking user presence.
  """

  use Phoenix.Presence,
    otp_app: :app,
    pubsub_server: App.PubSub
end
