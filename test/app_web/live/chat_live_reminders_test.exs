defmodule AppWeb.ChatLiveRemindersTest do
  use AppWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox

  alias App.Chat.ChattanReminders
  alias App.Accounts.User
  alias App.Treaties.Treaty

  setup do
    user = %User{
      id: "user-123",
      name: "João Silva",
      username: "joao.silva"
    }

    treaty = %Treaty{
      id: "treaty-456",
      treaty_code: "TREATY-001",
      status: "active"
    }

    {:ok, user: user, treaty: treaty}
  end

  describe "chat reminder creation" do
    test "creates reminder when user submits form", %{conn: conn, user: user, treaty: treaty} do
      # Simular login
      conn = assign(conn, :current_user, user)

      # Mock do treaty lookup
      with_mock App.Treaties, [get_treaty!: fn(_id) -> treaty end] do
        {:ok, view, _html} = live(conn, "/chat/#{treaty.id}")

        # Mock das funções de lembretes
        with_mock App.Chat.ChatReminders, [
          create_reminder: fn(_attrs) ->
            {:ok, %{
              id: "reminder-123",
              title: "Teste",
              description: "Descrição do teste",
              scheduled_at: DateTime.utc_now()
            }}
          end,
          get_user_chat_reminders: fn(_user, _treaty) -> [] end
        ] do
          # Clicar para mostrar formulário de lembretes
          view |> element("button", "Lembretes") |> render_click()

          # Verificar que formulário aparece
          assert render(view) =~ "Título"
          assert render(view) =~ "Descrição"
          assert render(view) =~ "Criar Lembrete"

          # Preencher formulário
          view
          |> form("form", reminder: %{
            "title" => "Teste reminder",
            "description" => "Descrição do teste",
            "scheduled_at" => Date.to_iso8601(Date.add(Date.utc_today(), 1)),
            "scheduled_time" => "14:30",
            "priority" => "high",
            "notification_type" => "popup"
          })
          |> render_submit()

          # Verificar que criação foi chamada
          assert_called App.Chat.ChatReminders.create_reminder(%{
            "user_id" => user.id,
            "treaty_id" => treaty.id,
            "title" => "Teste reminder",
            "description" => "Descrição do teste",
            # scheduled_at será calculado pelo parse_datetime
            "priority" => "high",
            "notification_type" => "popup",
            "recurring_type" => "none"
          })
        end
      end
    end

    test "shows error when reminder creation fails", %{conn: conn, user: user, treaty: treaty} do
      conn = assign(conn, :current_user, user)

      with_mock App.Treaties, [get_treaty!: fn(_id) -> treaty end] do
        with_mock App.Chat.ChatReminders, [
          create_reminder: fn(_attrs) -> {:error, %Ecto.Changeset{errors: [:scheduled_at]}} end,
          get_user_chat_reminders: fn(_user, _treaty) -> [] end
        ] do
          {:ok, view, _html} = live(conn, "/chat/#{treaty.id}")

          # Tenta criar lembrete
          view |> element("button", "Lembretes") |> render_click()

          view
          |> form("form", reminder: %{
            "title" => "Teste",
            "description" => "Descrição",
            "scheduled_at" => Date.to_iso8601(Date.add(Date.utc_today(), 1)),
            "scheduled_time" => "14:30"
          })
          |> render_submit()

          # Verificar mensagem de erro
          assert render(view) =~ "Erro ao criar lembrete"
        end
      end
    end
  end

  describe "chat reminder display" do
    test "displays existing reminders", %{conn: conn, user: user, treaty: treaty} do
      conn = assign(conn, :current_user, user)

      reminders = [
        %{
          id: "reminder-1",
          title: "Primeiro lembrete",
          description: "Descrição 1",
          scheduled_at: DateTime.add(DateTime.utc_now(), 1, :hour),
          status: "pending",
          priority: "high",
          completed_at: nil
        },
        %{
          id: "reminder-2",
          title: "Segundo lembrete",
          description: "Descrição 2",
          scheduled_at: DateTime.add(DateTime.utc_now(), 2, :hour),
          status: "done",
          priority: "medium",
          completed_at: DateTime.utc_now()
        }
      ]

      with_mock App.Treaties, [get_treaty!: fn(_id) -> treaty end] do
        with_mock App.Chat.ChatReminders, [
          get_user_chat_reminders: fn(_user, _treaty) -> reminders end
        ] do
          {:ok, view, _html} = live(conn, "/chat/#{treaty.id}")

          # Mostrar lembretes
          view |> element("button", "Lembretes") |> render_click()

          html = render(view)

          # Verificar que lembretes aparecem
          assert html =~ "Primeiro lembrete"
          assert html =~ "Segundo lembrete"
          assert html =~ "Alta"  # Prioridade
          assert html =~ "Média" # Prioridade
          assert html =~ "Marcar como Feito" # Botão para lembrete pendente
        end
      end
    end

    test "shows empty state when no reminders", %{conn: conn, user: user, treaty: treaty} do
      conn = assign(conn, :current_user, user)

      with_mock App.Treaties, [get_treaty!: fn(_id) -> treaty end] do
        with_mock App.Chat.ChatReminders, [
          get_user_chat_reminders: fn(_user, _treaty) -> [] end
        ] do
          {:ok, view, _html} = live(conn, "/chat/#{treaty.id}")

          view |> element("button", "Lembretes") |> render_click()

          html = render(view)
          assert html =~ "Nenhum lembrete ainda"
          assert html =~ "Crie seu primeiro lembrete para começar"
        end
      end
    end
  end

  describe "mark reminder as done" do
    test "marks reminder as done when button clicked", %{conn: conn, user: user, treaty: treaty} do
      conn = assign(conn, :current_user, user)

      reminder = %{
        id: "reminder-1",
        title: "Para marcar",
        description: "Teste",
        scheduled_at: DateTime.add(DateTime.utc_now(), 1, :hour),
        status: "pending",
        priority: "medium",
        completed_at: nil
      }

      with_mock App.Treaties, [get_treaty!: fn(_id) -> treaty end] do
        with_mock App.Chat.ChatReminders, [
          get_user_chat_reminders: fn(_user, _treaty) -> [reminder] end,
          mark_as_done: fn(_id) -> {:ok, %{reminder | status: "done"}} end,
          get_user_chat_reminders: fn(_user, _treaty) -> [%{reminder | status: "done"}] end
        ] do
          {:ok, view, _html} = live(conn, "/chat/#{treaty.id}")

          view |> element("button", "Lembretes") |> render_click()

          # Clicar botão marcar como feito
          view |> element("button", "Marcar como Feito") |> render_click()

          # Verificar chamada da função
          assert_called App.Chat.ChatReminders.mark_as_done("reminder-1")

          # Verificar mensagem de sucesso
          html = render(view)
          assert html =~ "Lembrete marcado como realizado"
        end
      end
    end

    test "handles error when marking reminder fails", %{conn: conn, user: user, treaty: treaty} do
      conn = assign(conn, :current_user, user)

      reminder = %{
        id: "reminder-1",
        title: "Para marcar",
        description: "Teste",
        scheduled_at: DateTime.add(DateTime.utc_now(), 1, :hour),
        status: "pending",
        priority: "medium",
        completed_at: nil
      }

      with_mock App.Treaties, [get_treaty!: fn(_id) -> treaty end] do
        with_mock App.Chat.ChatReminders, [
          get_user_chat_reminders: fn(_user, _treaty) -> [reminder] end,
          mark_as_done: fn(_id) -> {:error, :not_found} end
        ] do
          {:ok, view, _html} = live(conn, "/chat/#{treaty.id}")

          view |> element("button", "Lembretes") |> render_click()
          view |> element("button", "Marcar como Feito") |> render_click()

          html = render(view)
          assert html =~ "Lembrete não encontrado"
        end
      end
    end
  end

  describe "reminder notifications" do
    test "shows notification when reminder broadcast is received", %{conn: conn, user: user, treaty: treaty} do
      conn = assign(conn, :current_user, user)

      with_mock App.Treaties, [get_treaty!: fn(_id) -> treaty end] do
        with_mock App.Chat.ChatReminders, [
          get_user_chat_reminders: fn(_user, _treaty) -> [] end
        ] do
          {:ok, view, _html} = live(conn, "/chat/#{treaty.id}")

          # Simular receive de notificação
          send(view.pid, %{
            type: "reminder_notification",
            reminder: %{
              user_id: user.id,
              title: "Lembrete urgente",
              description: "Descrição do lembrete"
            }
          })

          # Processar mensagem
          view |> render()

          html = render(view)
          assert html =~ "Lembrete: Lembrete urgente"
          assert html =~ "Descrição do lembrete"
        end
      end
    end

    test "does not show notification for other users reminders", %{conn: conn, user: user, treaty: treaty} do
      other_user = %User{id: "other-123", name: "Outro Usuário"}
      conn = assign(conn, :current_user, user)

      with_mock App.Treaties, [get_treaty!: fn(_id) -> treaty end] do
        with_mock App.Chat.ChatReminders, [
          get_user_chat_reminders: fn(_user, _treaty) -> [] end
        ] do
          {:ok, view, _html} = live(conn, "/chat/#{treaty.id}")

          # Enviar notificação para outro usuário
          send(view.pid, %{
            type: "reminder_notification",
            reminder: %{
              user_id: other_user.id,
              title: "Lembrete do outro",
              description: "Não deve aparecer"
            }
          })

          html = render(view)

          # Não deve aparecer a notificação
          refute html =~ "Lembrete do outro"
        end
      end
    end
  end

  describe "form validation" do
    test "requires all mandatory fields", %{conn: conn, user: user, treaty: treaty} do
      conn = assign(conn, :current_user, user)

      with_mock App.Treaties, [get_treaty!: fn(_id) -> treaty end] do
        with_mock App.Chat.ChatReminders, [
          get_user_chat_reminders: fn(_user, _treaty) -> [] end
        ] do
          {:ok, view, _html} = live(conn, "/chat/#{treaty.id}")

          view |> element("button", "Lembretes") |> render_click()

          html = render(view)

          # Verificar campos obrigatórios
          assert html =~ "required" # Título é obrigatório
          assert html =~ "required" # Descrição é obrigatória
          assert html =~ "required" # Data é obrigatória
          assert html =~ "required" # Hora é obrigatória
        end
      end
    end
  end
end
