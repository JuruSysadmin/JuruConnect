defmodule App.NotificationsFixtures do
  @moduledoc """
  This module defines test fixtures for notifications.
  """

  alias App.Notifications

  @doc """
  Generate a notification.
  """
  def notification_fixture(attrs \\ %{}) do
    {:ok, notification} =
      attrs
      |> Enum.into(%{
        user_id: "test-user-id",
        treaty_id: "TRT123456",
        message_id: 1,
        notification_type: "new_message",
        title: "Nova mensagem",
        body: "Você recebeu uma nova mensagem",
        is_read: false,
        read_at: nil
      })
      |> Notifications.create_notification()

    notification
  end
end
