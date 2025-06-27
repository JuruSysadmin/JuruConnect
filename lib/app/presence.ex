defmodule ChatApp.Presence do
  @moduledoc """
  Provides presence tracking across channels and processes.
  """
  use Phoenix.Presence,
    otp_app: :chat_app,
    pubsub_server: ChatApp.PubSub
end
