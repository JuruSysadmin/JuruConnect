defmodule App.Chat.MessageLoadingTest do
  @moduledoc """
  Testes para investigar e corrigir o problema de carregamento do histórico de mensagens.

  Problema relatado: Chat não mantém histórico - mensagens só aparecem se o usuário
  estiver online no momento do envio.
  """

  use App.DataCase, async: true

  alias App.Chat
  alias App.Chat.Message
  alias App.Repo

  describe "carregamento do histórico de mensagens" do
    test "list_messages_for_order retorna mensagens existentes em ordem cronológica" do
      order_id = "TEST-ORDER-001"

      # Criar várias mensagens em momentos diferentes
      {:ok, msg1} = Chat.create_message(%{
        text: "Primeira mensagem",
        sender_id: "user1",
        sender_name: "Usuário 1",
        order_id: order_id,
        tipo: "mensagem"
      })

      # Simular um pequeno delay
      :timer.sleep(10)

      {:ok, msg2} = Chat.create_message(%{
        text: "Segunda mensagem",
        sender_id: "user2",
        sender_name: "Usuário 2",
        order_id: order_id,
        tipo: "mensagem"
      })

      :timer.sleep(10)

      {:ok, msg3} = Chat.create_message(%{
        text: "Terceira mensagem",
        sender_id: "user1",
        sender_name: "Usuário 1",
        order_id: order_id,
        tipo: "mensagem"
      })

      # Buscar mensagens usando a função que o ChatLive usa
      {:ok, messages, has_more} = Chat.list_messages_for_order(order_id, 50, 0)

      # Verificações
      assert length(messages) == 3
      assert has_more == false

      # Verificar ordem cronológica (asc)
      assert Enum.at(messages, 0).id == msg1.id
      assert Enum.at(messages, 1).id == msg2.id
      assert Enum.at(messages, 2).id == msg3.id

      # Verificar conteúdo das mensagens
      assert Enum.at(messages, 0).text == "Primeira mensagem"
      assert Enum.at(messages, 1).text == "Segunda mensagem"
      assert Enum.at(messages, 2).text == "Terceira mensagem"
    end

    test "list_messages_for_order funciona com limite e offset" do
      order_id = "TEST-ORDER-002"

      # Criar 5 mensagens
      messages_created = for i <- 1..5 do
        {:ok, msg} = Chat.create_message(%{
          text: "Mensagem #{i}",
          sender_id: "user1",
          sender_name: "Usuário 1",
          order_id: order_id,
          tipo: "mensagem"
        })
        :timer.sleep(10)
        msg
      end

      # Buscar primeiras 3 mensagens
      {:ok, first_batch, has_more} = Chat.list_messages_for_order(order_id, 3, 0)

      assert length(first_batch) == 3
      assert has_more == true
      assert Enum.at(first_batch, 0).text == "Mensagem 1"
      assert Enum.at(first_batch, 2).text == "Mensagem 3"

      # Buscar próximas 2 mensagens (offset 3)
      {:ok, second_batch, has_more2} = Chat.list_messages_for_order(order_id, 3, 3)

      assert length(second_batch) == 2
      assert has_more2 == false
      assert Enum.at(second_batch, 0).text == "Mensagem 4"
      assert Enum.at(second_batch, 1).text == "Mensagem 5"
    end

    test "mensagens são persistidas corretamente no banco" do
      order_id = "TEST-ORDER-003"

      # Criar mensagem
      {:ok, created_msg} = Chat.create_message(%{
        text: "Mensagem de teste",
        sender_id: "user1",
        sender_name: "Usuário Teste",
        order_id: order_id,
        tipo: "mensagem",
        image_url: "https://exemplo.com/image.jpg"
      })

      # Buscar diretamente do banco
      db_message = Repo.get(Message, created_msg.id)

      assert db_message != nil
      assert db_message.text == "Mensagem de teste"
      assert db_message.sender_id == "user1"
      assert db_message.sender_name == "Usuário Teste"
      assert db_message.order_id == order_id
      assert db_message.tipo == "mensagem"
      assert db_message.image_url == "https://exemplo.com/image.jpg"
      assert db_message.inserted_at != nil

      # Buscar via função de contexto
      {:ok, messages, _} = Chat.list_messages_for_order(order_id)

      assert length(messages) == 1
      found_msg = List.first(messages)
      assert found_msg.id == created_msg.id
      assert found_msg.text == created_msg.text
    end

    test "send_message persiste e retorna mensagem corretamente" do
      order_id = "TEST-ORDER-004"

      # Usar send_message (função que o frontend usa)
      {:ok, sent_message} = Chat.send_message(
        order_id,
        "user1",
        "Usuário Teste",
        "Mensagem via send_message"
      )

      # Verificar que foi criada
      assert sent_message.id != nil
      assert sent_message.text == "Mensagem via send_message"
      assert sent_message.order_id == order_id

      # Verificar que pode ser encontrada
      {:ok, messages, _} = Chat.list_messages_for_order(order_id)

      assert length(messages) == 1
      assert List.first(messages).id == sent_message.id
    end

    test "mensagens antigas são carregadas mesmo depois de muito tempo" do
      order_id = "TEST-ORDER-005"

      # Criar mensagem "antiga" (simulando tempo passado)
      old_datetime = DateTime.add(DateTime.utc_now(), -3600, :second) # 1 hora atrás

      changeset = Message.changeset(%Message{}, %{
        text: "Mensagem antiga",
        sender_id: "user1",
        sender_name: "Usuário Antigo",
        order_id: order_id,
        tipo: "mensagem"
      })

      # Inserir com timestamp antigo manualmente
      {:ok, old_message} = changeset
        |> Ecto.Changeset.force_change(:inserted_at, old_datetime)
        |> Ecto.Changeset.force_change(:updated_at, old_datetime)
        |> Repo.insert()

      # Criar mensagem nova
      {:ok, new_message} = Chat.create_message(%{
        text: "Mensagem nova",
        sender_id: "user2",
        sender_name: "Usuário Novo",
        order_id: order_id,
        tipo: "mensagem"
      })

      # Buscar todas as mensagens
      {:ok, messages, _} = Chat.list_messages_for_order(order_id)

      assert length(messages) == 2

      # Verificar ordem cronológica (antiga primeiro)
      assert Enum.at(messages, 0).id == old_message.id
      assert Enum.at(messages, 1).id == new_message.id

      assert Enum.at(messages, 0).text == "Mensagem antiga"
      assert Enum.at(messages, 1).text == "Mensagem nova"
    end

    test "diferentes order_ids não interferem entre si" do
      order_id_1 = "TEST-ORDER-A"
      order_id_2 = "TEST-ORDER-B"

      # Criar mensagens em pedidos diferentes
      {:ok, _msg_a1} = Chat.create_message(%{
        text: "Mensagem A1",
        sender_id: "user1",
        sender_name: "User 1",
        order_id: order_id_1,
        tipo: "mensagem"
      })

      {:ok, _msg_b1} = Chat.create_message(%{
        text: "Mensagem B1",
        sender_id: "user2",
        sender_name: "User 2",
        order_id: order_id_2,
        tipo: "mensagem"
      })

      {:ok, _msg_a2} = Chat.create_message(%{
        text: "Mensagem A2",
        sender_id: "user1",
        sender_name: "User 1",
        order_id: order_id_1,
        tipo: "mensagem"
      })

      # Verificar isolamento
      {:ok, messages_a, _} = Chat.list_messages_for_order(order_id_1)
      {:ok, messages_b, _} = Chat.list_messages_for_order(order_id_2)

      assert length(messages_a) == 2
      assert length(messages_b) == 1

      assert Enum.all?(messages_a, &(&1.order_id == order_id_1))
      assert Enum.all?(messages_b, &(&1.order_id == order_id_2))
    end
  end

  describe "debugging do problema específico" do
    test "simula o cenário do problema: usuário sai e volta" do
      order_id = "TEST-PROBLEM-001"

      # Usuário 1 envia mensagem
      {:ok, msg1} = Chat.send_message(order_id, "user1", "João", "Olá!")

      # Simular que usuário 2 não estava online
      # Usuário 2 entra no chat agora - deve ver a mensagem histórica
      {:ok, messages, _} = Chat.list_messages_for_order(order_id, 50, 0)

      # Usuário 2 DEVE ver a mensagem de João
      assert length(messages) == 1
      assert List.first(messages).text == "Olá!"
      assert List.first(messages).sender_name == "João"

      # Usuário 2 responde
      {:ok, msg2} = Chat.send_message(order_id, "user2", "Maria", "Oi João!")

      # Buscar novamente - deve ter 2 mensagens em ordem
      {:ok, updated_messages, _} = Chat.list_messages_for_order(order_id, 50, 0)

      assert length(updated_messages) == 2
      assert Enum.at(updated_messages, 0).text == "Olá!"
      assert Enum.at(updated_messages, 1).text == "Oi João!"
    end

    test "verifica query SQL gerada pela função list_messages_for_order" do
      order_id = "TEST-SQL-001"

      # Criar algumas mensagens
      Enum.each(1..3, fn i ->
        Chat.create_message(%{
          text: "Mensagem SQL #{i}",
          sender_id: "user1",
          sender_name: "Usuário SQL",
          order_id: order_id,
          tipo: "mensagem"
        })
        :timer.sleep(10)
      end)

      # Esta função deve gerar:
      # SELECT ... FROM messages WHERE order_id = ? ORDER BY inserted_at ASC LIMIT ? OFFSET ?
      {:ok, messages, has_more} = Chat.list_messages_for_order(order_id, 2, 0)

      assert length(messages) == 2
      assert has_more == true

      # Verificar que a ordem está correta (ASC por inserted_at)
      first_inserted = Enum.at(messages, 0).inserted_at
      second_inserted = Enum.at(messages, 1).inserted_at

      assert DateTime.compare(first_inserted, second_inserted) == :lt
    end
  end
end
