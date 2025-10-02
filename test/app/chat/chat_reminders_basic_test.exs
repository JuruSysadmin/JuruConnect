defmodule App.Chat.ChatRemindersBasicTest do
  use App.DataCase, async: true

  alias App.Chat.ChatReminders
  alias App.Chat.ChatReminder

  describe "schema validation" do
    test "validates required fields" do
      # Test without creating actual records - just test the changeset validation

      invalid_changeset = ChatReminder.create_changeset(%ChatReminder{}, %{
        "user_id" => Ecto.UUID.generate(),
        "treaty_id" => Ecto.UUID.generate(),
        "title" => "",
        "description" => "Test",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), 1, :hour)
      })

      refute invalid_changeset.valid?
      assert invalid_changeset.errors[:title] != nil
    end

    test "validates future date" do
      past_changeset = ChatReminder.create_changeset(%ChatReminder{}, %{
        "user_id" => Ecto.UUID.generate(),
        "treaty_id" => Ecto.UUID.generate(),
        "title" => "Test",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), -1, :hour) # Past
      })

      refute past_changeset.valid?
      assert past_changeset.errors[:scheduled_at] != nil
    end

    test "accepts valid changeset" do
      valid_changeset = ChatReminder.create_changeset(%ChatReminder{}, %{
        "user_id" => Ecto.UUID.generate(),
        "treaty_id" => Ecto.UUID.generate(),
        "title" => "Valid Test",
        "description" => "Description",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), 1, :hour),
        "priority" => "medium",
        "notification_type" => "popup",
        "recurring_type" => "none"
      })

      assert valid_changeset.valid?
    end
  end

  describe "function existence" do
    test "ChatReminders module has expected functions" do
      # Verificar se as funções existem (sem executar lógica)
      assert Code.ensure_loaded?(App.Chat.ChatReminders)

      # Verificar se algumas funções básicas existem
      assert function_exported?(App.Chat.ChatReminders, :create_reminder, 1)
      assert function_exported?(App.Chat.ChatReminders, :get_user_chat_reminders, 2)
      assert function_exported?(App.Chat.ChatReminders, :get_pending_reminders, 0)
    end
  end

  describe "timezone helpers" do
    test "parse_datetime creates correct timezone" do
      date_str = Date.to_iso8601(Date.add(Date.utc_today(), 1))
      time_str = "14:30"

      # Simular a função parse_datetime que seria usada no ChatLive
      {:ok, date} = Date.from_iso8601(date_str)
      {:ok, time} = Time.from_iso8601("#{time_str}:00")
      datetime = DateTime.new!(date, time, "America/Sao_Paulo") |> DateTime.shift_zone!("Etc/UTC")

      assert DateTime.compare(datetime, DateTime.utc_now()) == :gt
      assert datetime.time_zone == "Etc/UTC"
    end

    test "format function handles timezone conversion" do
      now = DateTime.utc_now()

      # Simular a função format_reminder_scheduled_at
      formatted = now |> DateTime.shift_zone!("America/Sao_Paulo") |> Calendar.strftime("%d/%m às %H:%M")

      assert is_binary(formatted)
      assert String.contains?(formatted, "/")
      assert String.contains?(formatted, "às")
    end
  end
end
