defmodule App.App.TreatyRemindersTest do
  use App.DataCase, async: true

  alias App.Treaties
  alias App.Treaties.{Treaty, TreatyReminder}

  setup do
    # Limpar dados anteriores
    App.Repo.delete_all(App.Chat.Message)
    App.Repo.delete_all(App.Treaties.TreatyReminder)
    App.Repo.delete_all(App.Treaties.Treaty)
    App.Repo.delete_all(App.Accounts.User)
    App.Repo.delete_all("stores")

    # Criar store para o teste
    store_id = "550e8400-e29b-41d4-a716-446655440000"
    App.Repo.insert_all("stores", [
      %{
        id: Ecto.UUID.dump!(store_id),
        name: "Loja Teste",
        location: "Localização Teste",
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    ])

    # Criar usuário para os testes
    {:ok, user} = create_user(%{
      username: "testuser",
      name: "Test User",
      role: "admin",
      password: "password123",
      store_id: store_id
    })

    {:ok, treaty1} = create_treaty(%{
      title: "Pedido de Estoque",
      description: "Cliente solicitando quantidade de produtos",
      created_by: user.id,
      store_id: user.store_id,
      status: "active"
    })

    {:ok, treaty2} = create_treaty(%{
      title: "Dúvida sobre Pagamento",
      description: "Cliente com dúvidas sobre forma de pagamento",
      created_by: user.id,
      store_id: user.store_id,
      status: "active"
    })

    {:ok, treaty3} = create_treaty(%{
      title: "Pedido Urgent",
      description: "Pedido com alta prioridade",
      created_by: user.id,
      store_id: user.store_id,
      status: "closed"
    })

    %{user: user, treaty1: treaty1, treaty2: treaty2, treaty3: treaty3}
  end

  describe "get_inactive_treaties/1" do
    test "retorna apenas tratativas ativas sem mensagens há mais de 24 horas", %{
      treaty1: treaty1, treaty2: treaty2, treaty3: treaty3
    } do
      # Criar mensagem recente para treaty1 (mantém ativo)
      insert_message(treaty1.treaty_code, "Mensagem recente", ~N[2024-01-15 10:00:00])

      # Criar mensagem antiga para treaty2 (considerado inativo)
      insert_message(treaty2.treaty_code, "Mensagem antiga", ~N[2024-01-14 08:00:00])

      inactive_treaties = App.TreatyReminders.get_inactive_treaties(24)

      treaty_codes = Enum.map(inactive_treaties, & &1.treaty_code)
      assert treaty2.treaty_code in treaty_codes
      refute treaty1.treaty_code in treaty_codes
      refute treaty3.treaty_code in treaty_codes
    end

    test "respeita o limite de horas configurado" do
      inactive_treaties = App.TreatyReminders.get_inactive_treaties(1)
      # Não deveria retornar nenhuma tratativa com limite de 1 hora
      assert length(inactive_treaties) == 0
    end

    test "exclui tratativas já fechadas" do
      inactive_treaties = App.TreatyReminders.get_inactive_treaties(24)
      closed_treaties = Enum.filter(inactive_treaties, &(&1.status == "closed"))
      assert length(closed_treaties) == 0
    end
  end

  describe "create_reminder/2" do
    test "cria um lembrete para uma tratativa", %{treaty1: treaty1} do
      result = App.TreatyReminders.create_reminder(treaty1.id, "Tratativa inativa há mais de 24 horas")

      assert {:ok, reminder} = result
      assert reminder.treaty_id == treaty1.id
      assert reminder.message == "Tratativa inativa há mais de 24 horas"
      assert reminder.status == "pending"
      assert reminder.notified_at == nil
    end

    test "valida parâmetros obrigatórios" do
      result = App.TreatyReminders.create_reminder(nil, "Mensagem")

      assert {:error, changeset} = result
      assert "can't be blank" in errors_on(changeset).treaty_id
    end

    test "valida tamanho da mensagem" do
      long_message = String.duplicate("a", 1001)
      result = App.TreatyReminders.create_reminder("valid-id", long_message)

      assert {:error, changeset} = result
      assert "should be at most 1000 character(s)" in errors_on(changeset).message
    end
  end

  describe "mark_as_notified/1" do
    test "marca um lembrete como notificado", %{treaty1: treaty1} do
      {:ok, reminder} = App.TreatyReminders.create_reminder(treaty1.id, "Lembrete teste")

      result = App.TreatyReminders.mark_as_notified(reminder.id)

      assert {:ok, updated_reminder} = result
      assert updated_reminder.status == "notified"
      assert updated_reminder.notified_at != nil
    end

    test "retorna erro quando lembrete não existe" do
      invalid_id = Ecto.UUID.generate()
      result = App.TreatyReminders.mark_as_notified(invalid_id)
      assert {:error, :not_found} = result
    end
  end

  describe "get_pending_reminders/0" do
    test "retorna apenas lembretes pendentes", %{treaty1: treaty1, treaty2: treaty2} do
      # Criar lembretes
      {:ok, _} = App.TreatyReminders.create_reminder(treaty1.id, "Lembrete 1")
      {:ok, reminder2} = App.TreatyReminders.create_reminder(treaty2.id, "Lembrete 2")

      # Marcar um como notificado
      App.TreatyReminders.mark_as_notified(reminder2.id)

      pending_reminders = App.TreatyReminders.get_pending_reminders()

      assert length(pending_reminders) == 1
      assert Enum.all?(pending_reminders, &(&1.status == "pending"))
    end
  end

  describe "automatic_reminder_creation/1" do
    test "cria lembretes automaticamente para tratativas inativas", %{treaty2: treaty2} do
      # Garantir que treaty2 está inativo
      insert_message(treaty2.treaty_code, "Mensagem antiga", ~N[2024-01-14 08:00:00])

      result = App.TreatyReminders.automatic_reminder_creation(24)

      assert {:ok, count} = result
      assert count > 0

      # Verificar se foi criado um lembrete para treaty2
      reminders = App.TreatyReminders.get_pending_reminders()
      treaty_ids = Enum.map(reminders, & &1.treaty_id)
      assert treaty2.id in treaty_ids
    end

    test "não cria lembretes duplicados para a mesma tratativa", %{treaty2: treaty2} do
      # Criar primeiro lembrete
      App.TreatyReminders.create_reminder(treaty2.id, "Lembrete já existe")

      insert_message(treaty2.treaty_code, "Mensagem antiga", ~N[2024-01-14 08:00:00])

      result = App.TreatyReminders.automatic_reminder_creation(24)

      assert {:ok, count} = result
      assert count == 0  # Contagem 0 porque já existe um lembrete pendente
    end
  end

  describe "get_reminder_stats/0" do
    test "retorna estatísticas corretas dos lembretes", %{
      treaty1: treaty1, treaty2: treaty2, treaty3: treaty3
    } do
      # Criar diferentes tipos de lembretes
      {:ok, _} = App.TreatyReminders.create_reminder(treaty1.id, "Pendente 1")
      {:ok, _} = App.TreatyReminders.create_reminder(treaty2.id, "Pendente 2")
      {:ok, reminder3} = App.TreatyReminders.create_reminder(treaty3.id, "Notificado")

      # Marcar um como notificado
      App.TreatyReminders.mark_as_notified(reminder3.id)

      stats = App.TreatyReminders.get_reminder_stats()

      assert stats.total_reminders == 3
      assert stats.pending_reminders == 2
      assert stats.notified_reminders == 1
      assert stats.reminder_rate > 0.0
    end
  end

  # Funções auxiliares de teste
  defp create_user(attrs) do
    App.Accounts.create_user(attrs)
  end

  defp create_treaty(attrs) do
    Treaties.create_treaty(attrs)
  end

  defp insert_message(treaty_code, content, inserted_at) do
    message_attrs = %{
      treaty_id: treaty_code,
      content: content,
      user_name: "Test User",
      sender_name: "Test User"
    }

    %App.Chat.Message{}
    |> App.Chat.Message.changeset(message_attrs)
    |> Ecto.Changeset.put_change(:inserted_at, inserted_at)
    |> Ecto.Changeset.put_change(:updated_at, inserted_at)
    |> App.Repo.insert!()
  end
end
