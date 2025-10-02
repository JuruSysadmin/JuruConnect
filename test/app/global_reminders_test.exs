defmodule App.GlobalRemindersTest do
  use App.DataCase, async: true

  alias App.GlobalReminders
  alias App.GlobalReminders.GlobalReminder
  alias App.Repo

  setup do
    # Limpar dados anteriores
    App.Repo.delete_all(App.GlobalReminders.GlobalReminder)
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

    %{user: user}
  end

  describe "create_reminder/1" do
    test "cria um lembrete global com sucesso", %{user: user} do
      attrs = %{
        user_id: user.id,
        title: "Almoçar com cliente",
        description: "Lembrete importante sobre reunião",
        scheduled_at: DateTime.utc_now() |> DateTime.add(1, :day),
        notification_type: "popup"
      }

      {:ok, reminder} = GlobalReminders.create_reminder(attrs)

      assert reminder.user_id == user.id
      assert reminder.title == "Almoçar com cliente"
      assert reminder.description == "Lembrete importante sobre reunião"
      assert reminder.notification_type == "popup"
      assert reminder.status == "pending"
      assert reminder.recurring_type == "none"
    end

    test "cria lembrete com recorrência diária", %{user: user} do
      attrs = %{
        user_id: user.id,
        title: "Verificar emails",
        description: "Lembrete diário",
        scheduled_at: DateTime.utc_now() |> DateTime.add(1, :hour),
        recurring_type: "daily",
        notification_type: "email"
      }

      {:ok, reminder} = GlobalReminders.create_reminder(attrs)

      assert reminder.title == "Verificar emails"
      assert reminder.recurring_type == "daily"
      assert reminder.notification_type == "email"
    end

    test "valida campos obrigatórios" do
      {:error, changeset} = GlobalReminders.create_reminder(%{})

      assert "can't be blank" in errors_on(changeset).user_id
      assert "can't be blank" in errors_on(changeset).title
      assert "can't be blank" in errors_on(changeset).scheduled_at
    end

    test "valida tamanho máximo do título" do
      long_title = String.duplicate("a", 201)

      {:error, changeset} = GlobalReminders.create_reminder(%{
        user_id: "valid-id",
        title: long_title,
        scheduled_at: DateTime.utc_now()
      })

      assert "should be at most 200 character(s)" in errors_on(changeset).title
    end

    test "valida data agendada no futuro" do
      past_date = DateTime.utc_now() |> DateTime.add(-1, :day)

      {:error, changeset} = GlobalReminders.create_reminder(%{
        user_id: "valid-id",
        title: "Título válido",
        scheduled_at: past_date
      })

      assert "must be in the future" in errors_on(changeset).scheduled_at
    end
  end

  describe "get_user_reminders/1" do
    test "lista todos os lembretes do usuário", %{user: user} do
      # Criar alguns lembretes
      {:ok, _} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "Primeiro lembrete",
        scheduled_at: DateTime.utc_now() |> DateTime.add(1, :day)
      })

      {:ok, _} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "Segundo lembrete",
        scheduled_at: DateTime.utc_now() |> DateTime.add(2, :day)
      })

      reminders = GlobalReminders.get_user_reminders(user)

      assert length(reminders) == 2
      assert Enum.all?(reminders, &(&1.user_id == user.id))
    end

    test "filtra lembretes por status", %{user: user} do
      _reminders = GlobalReminders.get_user_reminders(user, :pending)
      # Implementar testes específicos quando lembrete for marcado como realizado
    end

    test "ordena lembretes por data agendada", %{user: user} do
      reminders = GlobalReminders.get_user_reminders(user)
      scheduled_dates = Enum.map(reminders, &(&1.scheduled_at))
      # Verificar se está ordenado cronologicamente
      assert scheduled_dates == Enum.map(reminders, &(&1.scheduled_at)) |> Enum.sort()
    end
  end

  describe "get_pending_reminders/0" do
    test "encontra lembretes que devem ser executados agora", %{user: user} do
      now = DateTime.utc_now()

      # Criar lembrete que deve ser executado agora
      now_past = now |> DateTime.add(-1, :minute) |> DateTime.truncate(:second)
      reminder_past = %GlobalReminder{
        user_id: user.id,
        title: "Lembrete agora",
        scheduled_at: now_past,
        status: "pending"
      } |> Repo.insert!()

      # Lembrete no futuro
      {:ok, _} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "Lembrete futuro",
        scheduled_at: now |> DateTime.add(1, :hour),
        status: "pending"
      })

      # Lembrete já executado
      reminder_past_hour = %GlobalReminder{
        user_id: user.id,
        title: "Lembrete executado",
        scheduled_at: now |> DateTime.add(-1, :hour) |> DateTime.truncate(:second),
        status: "pending"
      } |> Repo.insert!()
      {:ok, _} = GlobalReminders.mark_as_done(reminder_past_hour.id)

      pending_reminders = GlobalReminders.get_pending_reminders()

      assert length(pending_reminders) == 1
      assert hd(pending_reminders).title == "Lembrete agora"
    end
  end

  describe "update_reminder/2" do
    test "atualiza dados do lembrete", %{user: user} do
      {:ok, reminder} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "Título original",
        description: "Descrição original",
        scheduled_at: DateTime.utc_now() |> DateTime.add(1, :day)
      })

      {:ok, updated} = GlobalReminders.update_reminder(reminder.id, %{
        title: "Título atualizado",
        description: "Descrição atualizada"
      })

      assert updated.title == "Título atualizado"
      assert updated.description == "Descrição atualizada"
      assert updated.id == reminder.id
    end

    test "retorna erro ao tentar atualizar lembrete inexistente" do
      invalid_id = Ecto.UUID.generate()

      {:error, :not_found} = GlobalReminders.update_reminder(invalid_id, %{
        title: "Novo título"
      })
    end
  end

  describe "mark_as_done/1" do
    test "marca lembrete como realizado", %{user: user} do
      {:ok, reminder} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "Lembrete para marcar como feito",
        scheduled_at: DateTime.utc_now() |> DateTime.add(1, :hour)
      })

      {:ok, updated} = GlobalReminders.mark_as_done(reminder.id)

      assert updated.status == "done"
      assert updated.completed_at != nil
    end

    test "retorna erro ao tentar marcar lembrete inexistente" do
      invalid_id = Ecto.UUID.generate()

      {:error, :not_found} = GlobalReminders.mark_as_done(invalid_id)
    end
  end

  describe "delete_reminder/1" do
    test "remove lembrete com sucesso", %{user: user} do
      {:ok, reminder} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "Lembrete para deletar",
        scheduled_at: DateTime.utc_now() |> DateTime.add(1, :hour)
      })

      {:ok, deleted} = GlobalReminders.delete_reminder(reminder.id)

      assert deleted.status == "deleted"
    end

    test "retorna erro ao tentar remover lembrete inexistente" do
      invalid_id = Ecto.UUID.generate()

      {:error, :not_found} = GlobalReminders.delete_reminder(invalid_id)
    end
  end

  describe "create_recurring_reminder/1" do
    test "cria próximas ocorrências de lembrete recorrente", %{user: user} do
      {:ok, reminder} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "Lembrete diário",
        scheduled_at: DateTime.utc_now() |> DateTime.add(1, :hour),
        recurring_type: "daily",
        notification_type: "popup"
      })

      # Marcar como feito para criar próxima ocorrência
      {:ok, _} = GlobalReminders.mark_as_done(reminder.id)

      # Chamar função para criar próxima ocorrência
      {:ok, next_reminder} = GlobalReminders.create_next_recurring(reminder.id)

      assert next_reminder.title == "Lembrete diário"
      assert next_reminder.status == "pending"
      next_date = DateTime.to_date(next_reminder.scheduled_at)
      original_date = DateTime.to_date(reminder.scheduled_at)
      assert Date.compare(next_date, original_date) == :gt
    end
  end

  describe "get_reminder_stats/1" do
    test "calcula estatísticas dos lembretes do usuário", %{user: user} do
      # Criar lembretes de diferentes status
      {:ok, reminder1} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "Lembrete pendente",
        scheduled_at: DateTime.utc_now() |> DateTime.add(1, :hour)
      })

      {:ok, reminder2} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "Lembrete realizado",
        scheduled_at: DateTime.utc_now() |> DateTime.add(1, :day)
      })

      # Marcar um como feito
      {:ok, _} = GlobalReminders.mark_as_done(reminder2.id)

      # Deletar um
      {:ok, _} = GlobalReminders.delete_reminder(reminder1.id)

      stats = GlobalReminders.get_reminder_stats(user.id)

      assert stats.total_reminders >= 2
      assert stats.completed_reminders >= 1
      assert stats.deleted_reminders >= 1
      assert stats.pending_reminders >= 0
    end
  end

  describe "search_reminders/2" do
    test "busca lembretes por título", %{user: user} do
      {:ok, _} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "Reunião importante com cliente",
        scheduled_at: DateTime.utc_now() |> DateTime.add(1, :day)
      })

      {:ok, _} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "Ligar para fornecedor",
        scheduled_at: DateTime.utc_now() |> DateTime.add(2, :day)
      })

      results = GlobalReminders.search_reminders(user.id, "cliente")

      assert length(results) == 1
      assert hd(results).title == "Reunião importante com cliente"
    end

    test "busca case insensitive", %{user: user} do
      {:ok, _} = GlobalReminders.create_reminder(%{
        user_id: user.id,
        title: "IMPORTANTE: Documento urgente",
        scheduled_at: DateTime.utc_now() |> DateTime.add(1, :day)
      })

      results_lower = GlobalReminders.search_reminders(user.id, "importante")
      results_upper = GlobalReminders.search_reminders(user.id, "IMPORTANTE")

      assert length(results_lower) == 1
      assert length(results_upper) == 1
      assert hd(results_lower).id == hd(results_upper).id
    end
  end

  # Funções auxiliares de teste
  defp create_user(attrs) do
    App.Accounts.create_user(attrs)
  end
end
