defmodule App.ChatTest do
  @moduledoc """
  Testes para o contexto de Chat, incluindo funcionalidades de notificações
  e marcação em lote de mensagens como lidas.
  """

  use App.DataCase, async: true

  alias App.Chat
  alias App.Minio
  alias App.Chat.Message
  alias App.Repo
  alias App.Factory

  @valid_attrs %{
    order_id: "123456",
    sender_id: "user1",
    text: "Mensagem com imagem"
  }

  test "envia mensagem com upload de imagem e salva image_url" do
    # Simule um arquivo temporário
    File.write!("/tmp/teste.jpg", "fake image content")
    filename = "user1_test_image.jpg"

    # Simule upload para o MinIO
    {:ok, image_url} = Minio.upload_file("/tmp/teste.jpg", filename)

    # Envie a mensagem com image_url
    {:ok, msg} =
      Chat.send_message(
        @valid_attrs.order_id,
        @valid_attrs.sender_id,
        @valid_attrs.text,
        image_url
      )

    assert msg.image_url == image_url
    assert String.contains?(msg.image_url, filename)
  end

  describe "bulk_mark_messages_read/2" do
    test "marks multiple messages as read successfully" do
      user1 = create_user("user1")
      user2 = create_user("user2")
      order_id = "ORDER-001"

      # Criar 3 mensagens do user1 para user2
      {:ok, msg1} = Chat.create_message(%{text: "Mensagem 1", sender_id: user1.id, sender_name: user1.username, order_id: order_id})
      {:ok, msg2} = Chat.create_message(%{text: "Mensagem 2", sender_id: user1.id, sender_name: user1.username, order_id: order_id})
      {:ok, msg3} = Chat.create_message(%{text: "Mensagem 3", sender_id: user1.id, sender_name: user1.username, order_id: order_id})

      # Marcar todas como lidas pelo user2
      {:ok, count} = Chat.bulk_mark_messages_read(order_id, user2.id)

      assert count == 3

      # Verificar se todas foram marcadas como lidas
      updated_msg1 = Repo.get(Chat.Message, msg1.id)
      updated_msg2 = Repo.get(Chat.Message, msg2.id)
      updated_msg3 = Repo.get(Chat.Message, msg3.id)

      assert user2.id in updated_msg1.read_by
      assert user2.id in updated_msg2.read_by
      assert user2.id in updated_msg3.read_by
    end

    test "ignores messages already read by user" do
      user1 = create_user("user1")
      user2 = create_user("user2")
      order_id = "ORDER-002"

      {:ok, msg1} = Chat.create_message(%{text: "Mensagem 1", sender_id: user1.id, sender_name: user1.username, order_id: order_id})
      {:ok, msg2} = Chat.create_message(%{text: "Mensagem 2", sender_id: user1.id, sender_name: user1.username, order_id: order_id})

      # Marcar msg1 como lida primeiro
      {:ok, _} = Chat.mark_message_read(msg1.id, user2.id)

      # Bulk read deve contar apenas msg2
      {:ok, count} = Chat.bulk_mark_messages_read(order_id, user2.id)

      assert count == 1
    end

    test "ignores messages sent by the same user" do
      user1 = create_user("user1")
      order_id = "ORDER-003"

      {:ok, _msg1} = Chat.create_message(%{text: "Minha mensagem", sender_id: user1.id, sender_name: user1.username, order_id: order_id})

      # Usuário não deve marcar suas próprias mensagens como lidas
      {:ok, count} = Chat.bulk_mark_messages_read(order_id, user1.id)

      assert count == 0
    end
  end

  describe "get_unread_count/2" do
    test "returns correct unread count" do
      user1 = create_user("user1")
      user2 = create_user("user2")
      order_id = "ORDER-004"

      {:ok, _msg1} = Chat.create_message(%{text: "Mensagem 1", sender_id: user1.id, sender_name: user1.username, order_id: order_id})
      {:ok, msg2} = Chat.create_message(%{text: "Mensagem 2", sender_id: user1.id, sender_name: user1.username, order_id: order_id})

      # Marcar apenas msg2 como lida
      {:ok, _} = Chat.mark_message_read(msg2.id, user2.id)

      {:ok, count} = Chat.get_unread_count(order_id, user2.id)
      assert count == 1
    end

    test "returns zero for user with all messages read" do
      user1 = create_user("user1")
      user2 = create_user("user2")
      order_id = "ORDER-005"

      {:ok, msg1} = Chat.create_message(%{text: "Mensagem 1", sender_id: user1.id, sender_name: user1.username, order_id: order_id})
      {:ok, _} = Chat.mark_message_read(msg1.id, user2.id)

      {:ok, count} = Chat.get_unread_count(order_id, user2.id)
      assert count == 0
    end
  end

  describe "notification events" do
    test "bulk read sends notification to senders" do
      user1 = create_user("user1")
      user2 = create_user("user2")
      order_id = "ORDER-006"

      # Subscrever ao tópico de notificações do user1
      Phoenix.PubSub.subscribe(App.PubSub, "notifications:#{user1.id}")

      {:ok, _msg1} = Chat.create_message(%{text: "Mensagem 1", sender_id: user1.id, sender_name: user1.username, order_id: order_id})

      # Bulk read deve enviar notificação
      {:ok, _count} = Chat.bulk_mark_messages_read(order_id, user2.id)

      assert_receive {:bulk_read_notification, %{count: 1, reader_id: user2_id, sender_id: user1_id, order_id: ^order_id}}
      assert user2_id == user2.id
      assert user1_id == user1.id
    end

    test "message read sends notification to sender" do
      user1 = create_user("user1")
      user2 = create_user("user2")
      order_id = "ORDER-007"

      # Subscrever ao tópico de notificações do user1
      Phoenix.PubSub.subscribe(App.PubSub, "notifications:#{user1.id}")

      {:ok, msg1} = Chat.create_message(%{text: "Mensagem 1", sender_id: user1.id, sender_name: user1.username, order_id: order_id})

      # Marcar mensagem como lida
      {:ok, _} = Chat.mark_message_read(msg1.id, user2.id)

      assert_receive {:message_read_notification, %{message_id: msg_id, reader_id: user2_id, sender_id: user1_id}}
      assert msg_id == msg1.id
      assert user2_id == user2.id
      assert user1_id == user1.id
    end
  end

  describe "mentions and replies" do
    test "create_message with mentions extracts mentioned users" do
      user1 = create_user("usuario1")
      user2 = create_user("usuario2")
      user3 = create_user("usuario3")
      order_id = "ORDER-MENTION-001"

      message_text = "Olá @usuario2 e @usuario3, precisamos conversar!"

      {:ok, message} = Chat.create_message(%{
        text: message_text,
        sender_id: user1.id,
        sender_name: user1.username,
        order_id: order_id
      })

      assert message.text == message_text
      assert message.mentions == ["usuario2", "usuario3"]
      assert message.has_mentions == true
    end

    test "create_message without mentions sets empty mentions" do
      user1 = create_user("user1")
      order_id = "ORDER-NO-MENTION-001"

      {:ok, message} = Chat.create_message(%{
        text: "Mensagem sem menções",
        sender_id: user1.id,
        sender_name: user1.username,
        order_id: order_id
      })

      assert message.mentions == []
      assert message.has_mentions == false
    end

    test "create_message with reply_to sets parent message" do
      user1 = create_user("user1")
      user2 = create_user("user2")
      order_id = "ORDER-REPLY-001"

      # Criar mensagem original
      {:ok, original_message} = Chat.create_message(%{
        text: "Mensagem original",
        sender_id: user1.id,
        sender_name: user1.username,
        order_id: order_id
      })

      # Criar resposta
      {:ok, reply_message} = Chat.create_message(%{
        text: "Respondendo à mensagem",
        sender_id: user2.id,
        sender_name: user2.username,
        order_id: order_id,
        reply_to: original_message.id
      })

      assert reply_message.reply_to == original_message.id
      assert reply_message.is_reply == true
    end

    test "get_mentions_for_user returns messages where user is mentioned" do
      user1 = create_user("usuario1")
      user2 = create_user("usuario2")
      user3 = create_user("usuario3")
      order_id = "ORDER-MENTION-002"

      # Mensagem mencionando usuario2
      {:ok, msg1} = Chat.create_message(%{
        text: "Oi @usuario2, como vai?",
        sender_id: user1.id,
        sender_name: user1.username,
        order_id: order_id
      })

      # Mensagem mencionando usuario3
      {:ok, _msg2} = Chat.create_message(%{
        text: "Olá @usuario3, tudo bem?",
        sender_id: user1.id,
        sender_name: user1.username,
        order_id: order_id
      })

      # Mensagem sem menções
      {:ok, _msg3} = Chat.create_message(%{
        text: "Mensagem geral",
        sender_id: user1.id,
        sender_name: user1.username,
        order_id: order_id
      })

      mentions = Chat.get_mentions_for_user(order_id, user2.username)

      assert length(mentions) == 1
      assert hd(mentions).id == msg1.id
    end

    test "get_thread_messages returns message and its replies" do
      user1 = create_user("user1")
      user2 = create_user("user2")
      order_id = "ORDER-THREAD-001"

      # Mensagem original
      {:ok, original} = Chat.create_message(%{
        text: "Mensagem original",
        sender_id: user1.id,
        sender_name: user1.username,
        order_id: order_id
      })

      # Primeira resposta
      {:ok, reply1} = Chat.create_message(%{
        text: "Primeira resposta",
        sender_id: user2.id,
        sender_name: user2.username,
        order_id: order_id,
        reply_to: original.id
      })

      # Segunda resposta
      {:ok, reply2} = Chat.create_message(%{
        text: "Segunda resposta",
        sender_id: user1.id,
        sender_name: user1.username,
        order_id: order_id,
        reply_to: original.id
      })

      # Mensagem não relacionada
      {:ok, _other} = Chat.create_message(%{
        text: "Outra mensagem",
        sender_id: user1.id,
        sender_name: user1.username,
        order_id: order_id
      })

      thread_messages = Chat.get_thread_messages(original.id)

      assert length(thread_messages) == 3
      message_ids = Enum.map(thread_messages, & &1.id)
      assert original.id in message_ids
      assert reply1.id in message_ids
      assert reply2.id in message_ids
    end

    test "send_mention_notifications notifies mentioned users" do
      user1 = create_user("usuario1")
      user2 = create_user("usuario2")
      user3 = create_user("usuario3")
      order_id = "ORDER-MENTION-NOTIF-001"

      # Subscrever aos tópicos de notificação
      Phoenix.PubSub.subscribe(App.PubSub, "mentions:#{user2.id}")
      Phoenix.PubSub.subscribe(App.PubSub, "mentions:#{user3.id}")

      {:ok, message} = Chat.create_message(%{
        text: "Oi @usuario2 e @usuario3, vejam isso!",
        sender_id: user1.id,
        sender_name: user1.username,
        order_id: order_id
      })

      # Verificar se as notificações foram enviadas
      assert_receive {:mention_notification, %{message_id: msg_id, mentioned_user: "usuario2", sender_id: sender_id}}
      assert_receive {:mention_notification, %{message_id: msg_id2, mentioned_user: "usuario3", sender_id: sender_id2}}

      assert msg_id == message.id
      assert msg_id2 == message.id
      assert sender_id == user1.id
      assert sender_id2 == user1.id
    end
  end

  # Funções auxiliares para os testes
  defp create_test_message(order_id, sender_id, sender_name, text) do
    {:ok, message} = Chat.send_message(order_id, sender_id, sender_name, text)
    message
  end

  # Função helper para criar usuários nos testes
  defp create_user(username) do
    Factory.insert(:user, %{username: username})
  end
end
