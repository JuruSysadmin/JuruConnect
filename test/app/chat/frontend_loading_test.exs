defmodule App.Chat.FrontendLoadingTest do
  @moduledoc """
  Testes específicos para investigar o problema de carregamento no frontend.

  Focando na função get_all_messages_with_notifications que pode estar
  interferindo com a exibição das mensagens históricas.
  """

  use App.DataCase, async: true

  alias App.Chat
  alias AppWeb.ChatLive

  describe "problema de get_all_messages_with_notifications" do
    test "função get_all_messages_with_notifications preserva mensagens do histórico" do
      # Simular dados como no ChatLive
      messages = [
        %{
          id: 1,
          text: "Mensagem histórica 1",
          sender_id: "user1",
          sender_name: "João",
          order_id: "123",
          tipo: "mensagem",
          inserted_at: DateTime.add(DateTime.utc_now(), -3600, :second),
          is_system: false
        },
        %{
          id: 2,
          text: "Mensagem histórica 2",
          sender_id: "user2",
          sender_name: "Maria",
          order_id: "123",
          tipo: "mensagem",
          inserted_at: DateTime.add(DateTime.utc_now(), -1800, :second),
          is_system: false
        }
      ]

      system_notifications = []

      # Simular a função privada (vamos testá-la através de reflexão ou criar uma cópia)
      result = merge_messages_and_notifications(messages, system_notifications)

      # Verificar que todas as mensagens históricas estão presentes
      assert length(result) == 2
      assert Enum.any?(result, &(&1.text == "Mensagem histórica 1"))
      assert Enum.any?(result, &(&1.text == "Mensagem histórica 2"))
    end

    test "função preserva ordem cronológica das mensagens" do
      older_message = %{
        id: 1,
        text: "Mensagem mais antiga",
        sender_id: "user1",
        sender_name: "João",
        order_id: "123",
        tipo: "mensagem",
        inserted_at: DateTime.add(DateTime.utc_now(), -7200, :second), # 2h atrás
        is_system: false
      }

      newer_message = %{
        id: 2,
        text: "Mensagem mais nova",
        sender_id: "user2",
        sender_name: "Maria",
        order_id: "123",
        tipo: "mensagem",
        inserted_at: DateTime.add(DateTime.utc_now(), -3600, :second), # 1h atrás
        is_system: false
      }

      messages = [newer_message, older_message] # Ordem embaralhada
      system_notifications = []

      result = merge_messages_and_notifications(messages, system_notifications)

      # Verificar ordem cronológica (mais antiga primeiro)
      assert length(result) == 2
      assert Enum.at(result, 0).text == "Mensagem mais antiga"
      assert Enum.at(result, 1).text == "Mensagem mais nova"
    end

    test "função mescla mensagens com notificações do sistema corretamente" do
      message = %{
        id: 1,
        text: "Mensagem normal",
        sender_id: "user1",
        sender_name: "João",
        order_id: "123",
        tipo: "mensagem",
        inserted_at: DateTime.add(DateTime.utc_now(), -1800, :second),
        is_system: false
      }

      notification = %{
        id: "system_1",
        text: "João entrou na conversa",
        sender_id: "system",
        sender_name: "Sistema",
        order_id: "123",
        tipo: "system_notification",
        inserted_at: DateTime.add(DateTime.utc_now(), -3600, :second),
        is_system: true
      }

      messages = [message]
      system_notifications = [notification]

      result = merge_messages_and_notifications(messages, system_notifications)

      # Verificar que ambos estão presentes e na ordem correta
      assert length(result) == 2
      assert Enum.at(result, 0).text == "João entrou na conversa"  # Mais antiga
      assert Enum.at(result, 1).text == "Mensagem normal"         # Mais nova
    end

    test "problema específico: mensagens não aparecem quando system_notifications está vazio" do
      # Este é o caso que está falhando - mensagens históricas com notificações vazias
      messages = [
        %{
          id: 1,
          text: "Esta mensagem deveria aparecer",
          sender_id: "user1",
          sender_name: "João",
          order_id: "123",
          tipo: "mensagem",
          inserted_at: DateTime.add(DateTime.utc_now(), -3600, :second),
          is_system: false
        }
      ]

      system_notifications = [] # Vazio como no mount inicial

      result = merge_messages_and_notifications(messages, system_notifications)

      # Esta mensagem DEVE aparecer
      assert length(result) == 1
      assert List.first(result).text == "Esta mensagem deveria aparecer"
    end
  end

  # Função helper que replica a lógica da função privada
  defp merge_messages_and_notifications(messages, system_notifications) do
    # Replicar exatamente a mesma lógica da função privada
    all_items = messages ++ system_notifications

    Enum.sort(all_items, fn a, b ->
      DateTime.compare(a.inserted_at, b.inserted_at) != :gt
    end)
  end
end
