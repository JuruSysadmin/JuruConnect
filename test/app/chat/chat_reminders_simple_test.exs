defmodule App.Chat.ChatRemindersSimpleTest do
  use App.DataCase, async: true

  alias App.Chat.ChatReminders
  alias App.Chat.ChatReminder

  describe "create_reminder/1" do
    test "creates a reminder with valid attributes" do
      attrs = %{
        "user_id" => Ecto.UUID.generate(),
        "treaty_id" => Ecto.UUID.generate(),
        "title" => "Revisar contrato",
        "description" => "Verificar cláusulas importantes",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), 1, :hour),
        "priority" => "high",
        "notification_type" => "popup",
        "recurring_type" => "none"
      }

      assert {:ok, %ChatReminder{} = reminder} = ChatReminders.create_reminder(attrs)
      assert reminder.title == "Revisar contrato"
      assert reminder.priority == "high"
      assert reminder.status == "pending"
    end

    test "returns error with invalid attributes" do
      attrs = %{
        "user_id" => Ecto.UUID.generate(),
        "title" => "",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), -1, :hour) # Passado
      }

      assert {:error, %Ecto.Changeset{}} = ChatReminders.create_reminder(attrs)
    end
  end

  describe "mark_as_done/1" do
    test "marks a pending reminder as done" do
      user_id = Ecto.UUID.generate()
      treaty_id = Ecto.UUID.generate()

      # Criar lembrete
      {:ok, reminder} = ChatReminders.create_reminder(%{
        "user_id" => user_id,
        "treaty_id" => treaty_id,
        "title" => "Para marcar",
        "description" => "Descrição do teste",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), 1, :hour),
        "priority" => "medium",
        "notification_type" => "popup",
        "recurring_type" => "none"
      })

      assert {:ok, %ChatReminder{} = updated} = ChatReminders.mark_as_done(reminder.id)
      assert updated.status == "done"
      assert updated.completed_at != nil
    end

    test "returns error for invalid reminder id" do
      fake_uuid = Ecto.UUID.generate()
      assert {:error, :not_found} = ChatReminders.mark_as_done(fake_uuid)
    end
  end

  describe "get_pending_chat_reminders/0" do
    test "returns reminders that should be executed now" do
      user_id = Ecto.UUID.generate()
      treaty_id = Ecto.UUID.generate()
      past_time = DateTime.add(DateTime.utc_now(), -30, :minute)

      # Criar lembrete do passado (deve ser executado)
      {:ok, _past} = ChatReminders.create_reminder(%{
        "user_id" => user_id,
        "treaty_id" => treaty_id,
        "title" => "Passado",
        "description" => "Descrição do teste",
        "scheduled_at" => past_time,
        "priority" => "medium",
        "notification_type" => "popup",
        "recurring_type" => "none"
      })

      # Criar lembrete do futuro (não deve ser executado)
      future_time = DateTime.add(DateTime.utc_now(), 1, :hour)
      {:ok, _future} = ChatReminders.create_reminder(%{
        "user_id" => Ecto.UUID.generate(),
        "treaty_id" => Ecto.UUID.generate(),
        "title" => "Futuro",
        "description" => "Descrição do teste",
        "scheduled_at" => future_time,
        "priority" => "medium",
        "notification_type" => "popup",
        "recurring_type" => "none"
      })

      pending = ChatReminders.get_pending_chat_reminders()

      assert length(pending) == 1
      assert hd(pending).title == "Passado"
    end
  end
end
