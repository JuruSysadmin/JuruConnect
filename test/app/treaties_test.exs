defmodule App.TreatiesTest do
  use App.DataCase, async: true

  alias App.Treaties
  alias App.Treaties.{Treaty, TreatyActivity}
  alias App.Accounts.User

  @store1_id "550e8400-e29b-41d4-a716-446655440000"
  @store2_id "550e8400-e29b-41d4-a716-446655440001"

  setup do
    # LIMPEZA: Remover dados anteriores para isolamento
    cleanup_test_data()

    # Criar stores para os testes
    App.Repo.insert_all("stores", [
      %{
        id: Ecto.UUID.dump!(@store1_id),
        name: "Loja Teste 1",
        location: "Localização Teste 1",
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      },
      %{
        id: Ecto.UUID.dump!(@store2_id),
        name: "Loja Teste 2",
        location: "Localização Teste 2",
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    ])

    # Criar usuários para os testes
    {:ok, user1} = create_user(%{
      username: "user1",
      name: "User One",
      role: "customer",
      password: "password123",
      store_id: @store1_id
    })

    {:ok, user2} = create_user(%{
      username: "user2",
      name: "User Two",
      role: "admin",
      password: "password123",
      store_id: @store2_id
    })

    {:ok, admin} = create_user(%{
      username: "admin",
      name: "Admin User",
      role: "admin",
      password: "password123",
      store_id: @store1_id
    })

    {:ok, user1: user1, user2: user2, admin: admin}
  end

  describe "get_admin_dashboard_stats/0" do
    test "calcula estatísticas corretas quando há tratativas", %{user1: user1, user2: user2, admin: admin} do
      # Arrange - Create treaties with different statuses and times
      now = DateTime.utc_now()

      # Treaty 1: Active (não conta para closed nem resolution time)
      {:ok, _treaty1} = create_treaty(%{
         title: "Tratativa Ativa",
         description: "Descrição da tratativa ativa",
         status: "active",
         created_by: user1.id,
         store_id: user1.store_id
       })

       # Treaty 2: Closed recently (closed_at, conta para resolution time)
       {:ok, treaty2} = create_treaty(%{
         title: "Tratativa Encerrada",
         description: "Descrição da tratativa encerrada",
         status: "closed",
         close_reason: "resolved",
         created_by: user1.id,
         store_id: user1.store_id,
         inserted_at: now |> DateTime.add(-2, :hour),
         closed_at: now |> DateTime.add(-1, :hour)
       })

       # Treaty 3: Closed longer ago
       {:ok, _treaty3} = create_treaty(%{
         title: "Tratativa Encerrada Antiga",
         description: "Descrição da tratativa encerrada antiga",
         status: "closed",
         close_reason: "cancelled",
         created_by: user2.id,
         store_id: user2.store_id,
         inserted_at: now |> DateTime.add(-10, :hour),
         closed_at: now |> DateTime.add(-8, :hour)
       })

       # Treaty 4: Another active treaty
       {:ok, _treaty4} = create_treaty(%{
         title: "Outra Tratativa Ativa",
         description: "Outra descrição de tratativa ativa",
         status: "active",
         created_by: user1.id,
         store_id: user1.store_id
       })

       # Create activity for reopened treaty (simulate reopening)
       {:ok, _activity} = create_activity(%{
         treaty_id: treaty2.id,
         user_id: admin.id,
         activity_type: "reopened",
         description: "Tratativa foi reaberta",
         activity_at: now
       })

       # Act
       stats = Treaties.get_admin_dashboard_stats()

       # Assert
       assert stats.total_treaties == 4
       assert stats.active_treaties == 2
       assert stats.closed_treaties == 2
       assert is_float(stats.average_resolution_time)
       assert stats.average_resolution_time > 0

       # Verification of close reasons
       close_reasons = stats.most_common_close_reasons
       assert length(close_reasons) == 2

       reasons_list = Enum.map(close_reasons, & &1.reason)
       assert "resolved" in reasons_list
       assert "cancelled" in reasons_list

       # Verification of reopen rate (1 reopened treaty out of 2 closed = 50%)
       assert stats.reopen_rate == 50.0

       # Verify status distribution
       assert length(stats.treaties_by_status) >= 2

       # Verify recent activities
       assert length(stats.recent_activities) <= 10
    end

    test "calcula estatísticas corretas quando não há tratativas" do
      # Act
      stats = Treaties.get_admin_dashboard_stats()

      # Assert
       assert stats.total_treaties == 0
       assert stats.active_treaties == 0
       assert stats.closed_treaties == 0
       assert stats.average_resolution_time == 0.0
       assert stats.reopen_rate == 0.0
       assert stats.most_common_close_reasons == []
       assert stats.treaties_by_status == []
       assert stats.recent_activities == []
    end
  end

  describe "get_total_treaties_count/0" do
    test "conta total de tratativas corretamente", %{user1: user1} do
      # Arrange
      {:ok, _treaty1} = create_treaty(%{
        title: "Tratativa 1",
        description: "Descrição 1",
        created_by: user1.id,
        store_id: user1.store_id
      })

      {:ok, _treaty2} = create_treaty(%{
        title: "Tratativa 2",
        description: "Descrição 2",
        created_by: user1.id,
        store_id: user1.store_id
      })

      # Act
      count = Treaties.get_total_treaties_count()

      # Assert
       assert count == 2
    end

    test "retorna 0 quando não há tratativas" do
      # Act
      count = Treaties.get_total_treaties_count()

      # Assert
       assert count == 0
    end
  end

  describe "get_active_treaties_count/0" do
    test "conta apenas tratativas ativas", %{user1: user1} do
      # Arrange
      {:ok, _active} = create_treaty(%{
        title: "Ativa",
        description: "Descrição",
        status: "active",
        created_by: user1.id,
        store_id: user1.store_id
      })

      {:ok, _closed} = create_treaty(%{
        title: "Fechada",
        description: "Descrição",
        status: "closed",
        created_by: user1.id,
        store_id: user1.store_id
      })

      # Act
      count = Treaties.get_active_treaties_count()

      # Assert
       assert count == 1
    end

    test "retorna 0 quando não há tratativas ativas" do
      # Act
      count = Treaties.get_active_treaties_count()

      # Assert
       assert count == 0
    end
  end

  describe "get_closed_treaties_count/0" do
    test "conta apenas tratativas encerradas", %{user1: user1} do
      # Arrange
      {:ok, _active} = create_treaty(%{
        title: "Ativa",
        description: "Descrição",
        status: "active",
        created_by: user1.id,
        store_id: user1.store_id
      })

      {:ok, _closed1} = create_treaty(%{
        title: "Fechada 1",
        description: "Descrição",
        status: "closed",
        created_by: user1.id,
        store_id: user1.store_id
      })

      {:ok, _closed2} = create_treaty(%{
        title: "Fechada 2",
        description: "Descrição",
        status: "closed",
        created_by: user1.id,
        store_id: user1.store_id
      })

      # Act
      count = Treaties.get_closed_treaties_count()

      # Assert
       assert count == 2
    end

    test "retorna 0 quando não há tratarivos encerrados" do
      # Act
      count = Treaties.get_closed_treaties_count()

      # Assert
       assert count == 0
    end
  end

  describe "get_average_resolution_time/0" do
    test "calcula tempo médio de resolução corretamente", %{user1: user1} do
      # Arrange
      now = DateTime.utc_now()

      # Treaty resolvida em 2 horas
      {:ok, _treaty1} = create_treaty(%{
        title: "Resolvida Rápido",
        description: "Descrição",
        status: "closed",
        created_by: user1.id,
        store_id: user1.store_id,
        inserted_at: now |> DateTime.add(-2, :hour),
        closed_at: now |> DateTime.add(-1, :hour)
      })

      # Treaty resolvida em 4 horas
      {:ok, _treaty2} = create_treaty(%{
        title: "Resolvida Lento",
        description: "Descrição",
        status: "closed",
        created_by: user1.id,
        store_id: user1.store_id,
        inserted_at: now |> DateTime.add(-6, :hour),
        closed_at: now |> DateTime.add(-4, :hour)
      })

      # Act
      average_time = Treaties.get_average_resolution_time()

      # Assert
      # Tempo médio deve ser (2 + 4) / 2 = 3 horas
      assert average_time == 3.0
    end

    test "retorna 0 quando não há tratatos encerrados" do
      # Act
      average_time = Treaties.get_average_resolution_time()

      # Assert
       assert average_time == 0.0
    end

    test "ignora treaties sem closed_at ou inserted_at", %{user1: user1} do
      # Arrange - Treaty marcada como closed mas sem timestamp
      {:ok, _treaty} = create_treaty(%{
        title: "Mal definida",
        description: "Descrição",
        status: "closed",
        created_by: user1.id,
        store_id: user1.store_id,
        inserted_at: nil,
        closed_at: nil
      })

      # Act
      average_time = Treaties.get_average_resolution_time()

      # Assert
       assert average_time == 0.0
    end
  end

  describe "get_reopen_rate/0" do
    test "calcula taxa de reabertura corretamente", %{user1: user1, admin: admin} do
      # Arrange
      now = DateTime.utc_now()

      # Criar treaties fechados
      {:ok, treaty1} = create_treaty(%{
        title: "Fechada",
        description: "Descrição",
        status: "closed",
        created_by: user1.id,
        store_id: user1.store_id
      })

      {:ok, _treaty2} = create_treaty(%{
        title: "Fechada",
        description: "Descrição",
        status: "closed",
        created_by: user1.id,
        store_id: user1.store_id
      })

      {:ok, _treaty3} = create_treaty(%{
        title: "Fechada",
        description: "Descrição",
        status: "closed",
        created_by: user1.id,
        store_id: user1.store_id
      })

      # Reabrir apenas uma das três (33.33%)
      {:ok, _activity} = create_activity(%{
        treaty_id: treaty1.id,
        user_id: admin.id,
        activity_type: "reopened",
        description: "Tratativa reaberta",
        activity_at: now
      })

      # Act
      reopen_rate = Treaties.get_reopen_rate()

      # Assert
      #  1 reopened out of 3 closed = 33.33%
      assert reopen_rate == 33.33
    end

    test "retorna 0 quando não há treativos encerrados" do
      # Act
      reopen_rate = Treaties.get_reopen_rate()

      # Assert
       assert reopen_rate == 0.0
    end

    test "retorna 0 quando não há atividades de reabertura" do
      # Arrange
      {:ok, _user} = create_user(%{
        username: "testuser",
        name: "Test User",
        role: "customer",
        password: "password123",
        store_id: "550e8400-e29b-41d4-a716-446655440002"
      })

      # Act
         reopen_rate = Treaties.get_reopen_rate()

      # Assert
         assert reopen_rate == 0.0
    end
  end

  describe "get_most_common_close_reasons/1" do
    test "retorna motivos mais comuns de fechamento", %{user1: user1} do
      # Arrange
      # Criar treaties with different close reasons
      close_reasons = ["resolved", "resolved", "cancelled", "duplicate", "duplicate", "duplicate"]

      Enum.each(close_reasons, fn reason ->
        {:ok, _treaty} = create_treaty(%{
          title: "Tratativa #{reason}",
          description: "Descrição",
          status: "closed",
          close_reason: reason,
          created_by: user1.id,
          store_id: user1.store_id
        })
      end)

      # Act
      results = Treaties.get_most_common_close_reasons()

      # Assert
       assert length(results) == 3 # Should have 3 different reasons

       # Should be ordered by count (descrinding)
       counts = Enum.map(results, & &1.count)
       assert counts == [3, 2, 1] # duplicate=3, resolved=2, cancelled=1

       reasons = Enum.map(results, & &1.reason)
       assert "duplicate" == List.first(reasons)
    end

    test "retorna array vazio quando não há reasonos de fechamento" do
      # Act
      results = Treaties.get_most_common_close_reasons()

      # Assert
       assert results == []
    end

    test "ignora treaties sem close_reason", %{user1: user1} do
      # Arrange - Treaty fechada mas sem motivo
      {:ok, _treaty} = create_treaty(%{
        title: "Sem motivo",
        description: "Descrição",
        status: "closed",
        close_reason: nil,
        created_by: user1.id,
        store_id: user1.store_id
      })

      # Act
      results = Treaties.get_most_common_close_reasons()

      # Assert
       assert results == []
    end

    test "respeita limite especificado", %{user1: user1} do
      # Arrange - Create multiple close reasons
      reasons = ["resolved", "cancelled", "duplicate", "invalid", "other"]

      Enum.each(reasons, fn reason ->
        {:ok, _treaty} = create_treaty(%{
          title: "Tratativa #{reason}",
          description: "Descrição",
          status: "closed",
          close_reason: reason,
          created_by: user1.id,
          store_id: user1.store_id
        })
      end)

      # Act
      limited_results = Treaties.get_most_common_close_reasons(3)

      # Assert
       assert length(limited_results) == 3
    end
  end

  describe "get_treaties_by_status/0" do
    test "retorna distribuição por status", %{user1: user1} do
      # Arrange
      statuses = ["active", "active", "closed", "closed", "closed", "cancelled"]

      Enum.each(Enum.with_index(statuses), fn {status, index} ->
        {:ok, _treaty} = create_treaty(%{
          title: "Tratativa #{index}",
          description: "Descrição",
          status: status,
          created_by: user1.id,
          store_id: user1.store_id
        })
      end)

      # Act
      results = Treaties.get_treaties_by_status()

      # Assert
       assert length(results) >= 3

       # Should include active, closed, and cancelled
       status_counts = Enum.into(results, %{}, fn item -> {item.status, item.count} end)

       assert Map.get(status_counts, "active") == 2
       assert Map.get(status_counts, "closed") == 3
       assert Map.get(status_counts, "cancelled") == 1
    end

    test "retorna array vazio quando não há treaties" do
      # Act
      results = Treaties.get_treaties_by_status()

      # Assert
       assert results == []
    end
  end

  describe "get_user_treaties_count/1" do
    test "conta treaties de um usuário específico", %{user1: user1, user2: user2} do
      # Arrange
      {:ok, _user1_treaty1} = create_treaty(%{
        title: "Tratativa 1",
        description: "Descrição",
         created_by: user1.id,
         store_id: user1.store_id
      })

      {:ok, _user1_treaty2} = create_treaty(%{
        title: "Tratativa 2",
        description: "Descrição",
        created_by: user1.id,
        store_id: user1.store_id
      })

      {:ok, _user2_treaty} = create_treaty(%{
        title: "Tratativa User 2",
        description: "Descrição",
        created_by: user2.id,
        store_id: user2.store_id
      })

      # Act
      user1_count = Treaties.get_user_treaties_count(user1.id)
      user2_count = Treaties.get_user_treaties_count(user2.id)

      # Assert
       assert user1_count == 2
       assert user2_count == 1
    end

      test "retorna 0 quando user não tem treaties" do
        # Act
        count = Treaties.get_user_treaties_count("550e8400-e29b-41d4-a716-446655440999")

        # Assert
         assert count == 0
      end
  end

  describe "get_user_reopen_rate/1" do
    test "calcula taxa de reabertura do usuário", %{user1: user1, admin: admin} do
      # Arrange
      now = DateTime.utc_now()

      # User tem 2 treaties fechados
      {:ok, treaty1} = create_treaty(%{
        title: "User Treaty 1",
        description: "Descrição",
        status: "closed",
        created_by: user1.id,
        store_id: user1.store_id
      })

      {:ok, treaty2} = create_treaty(%{
        title: "User Treaty 2",
        description: "Descrição",
        status: "closed",
        created_by: user1.id,
        store_id: user1.store_id
      })

      # Apenas uma foi reaberta (50%)
      {:ok, _activity} = create_activity(%{
        treaty_id: treaty1.id,
        user_id: admin.id,
        activity_type: "reopened",
        description: "Tratativa do usuário reaberta",
        activity_at: now
      })

      # Act
      user_reopen_rate = Treaties.get_user_reopen_rate(user1.id)

      # Assert
       assert user_reopen_rate == 50.0
    end

      test "retorna 0 para user sem treaties fechados" do
        # Act
        reopen_rate = Treaties.get_user_reopen_rate("550e8400-e29b-41d4-a716-446655440999")

        # Assert
         assert reopen_rate == 0.0
      end
  end

  describe "get_recent_activities/1" do
    test "busca atividades recentes", %{user1: user1, admin: admin} do
      # Arrange
      {:ok, treaty} = create_treaty(%{
        title: "Tratativa",
        description: "Descrição",
        created_by: user1.id,
        store_id: user1.store_id
      })

      now = DateTime.utc_now()

      # Criar algumas atividades
      {:ok, _activity1} = create_activity(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        activity_type: "created",
        description: "Tratativa criada",
        activity_at: now |> DateTime.add(-2, :hour)
      })

      {:ok, _activity2} = create_activity(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        activity_type: "message_sent",
        description: "Mensagem enviada",
        activity_at: now |> DateTime.add(-1, :hour)
      })

      {:ok, _activity3} = create_activity(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        activity_type: "closed",
        description: "Tratativa fechada",
        activity_at: now
      })

      # Act
      activities = Treaties.get_recent_activities(2)

      # Assert
       assert length(activities) == 2

       # Deve estar ordenado por activity_at desc
       [most_recent, second_recent] = activities
       assert most_recent.activity_type == "closed"
       assert second_recent.activity_type == "message_sent"
    end
  end

  describe "get_recent_activities_count/1" do
    test "busca actividades dos últimos 24h", %{user1: user1, admin: admin} do
      # Arrange
      {:ok, treaty} = create_treaty(%{
        title: "Tratativa",
        description: "Descrição",
        created_by: user1.id,
        store_id: user1.store_id
      })

      now = DateTime.utc_now()

      # Atividade recente (< 24h)
      {:ok, _recent} = create_activity(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        activity_type: "message_sent",
        description: "Mensagem recente",
        activity_at: now |> DateTime.add(-12, :hour)
      })

      # Atividade antiga (> 24h)
      {:ok, _old} = create_activity(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        activity_type: "created",
        description: "Atividade antiga",
        activity_at: now |> DateTime.add(-36, :hour)
      })

      # Act
      count = Treaties.get_recent_activities_count()

      # Assert
       assert count == 1  # Apenas a atividade recent should be counted
    end
  end

  # Helper functions for creating test data

  defp cleanup_test_data do
    # Limpar dados em ordem reversa das foreign keys para evitar erros de constraint
    App.Repo.delete_all("treaty_activities")
    App.Repo.delete_all("treaties")
    App.Repo.delete_all("users")
    App.Repo.delete_all("stores")
  end

  defp create_user(attrs) do
    # Generate a default UUID for store_id if not provided
    default_store_id = "550e8400-e29b-41d4-a716-446655440000"
    attrs_with_store =
      Map.put(attrs, :store_id, Map.get(attrs, :store_id, default_store_id))

    App.Accounts.create_user(attrs_with_store)
  end

  defp create_treaty(attrs) do
    default_attrs = %{
      title: "Test Treaty",
      description: "Test Description",
      treaty_code: "TEST#{System.unique_integer()}",
      store_id: "550e8400-e29b-41d4-a716-446655440000",
      created_by: "testuser"
    }

    attrs_with_defaults = Map.merge(default_attrs, attrs)
    Treaties.create_treaty(attrs_with_defaults)
  end

  defp create_activity(attrs) do
    default_attrs = %{
      treaty_id: "test-treaty",
      user_id: "test-user",
      activity_type: "created",
      description: "Test activity",
      activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    attrs_with_defaults = Map.merge(default_attrs, attrs)

    %TreatyActivity{}
    |> TreatyActivity.create_changeset(attrs_with_defaults)
    |> Repo.insert()
  end
end
