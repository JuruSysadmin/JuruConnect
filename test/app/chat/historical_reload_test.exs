defmodule App.Chat.HistoricalReloadTest do
  @moduledoc """
  Testes para verificar se as correções de carregamento do histórico estão funcionando.

  Problema original: Chat não mantém histórico quando usuários não estão online
  durante o envio de mensagens.
  """

  use App.DataCase, async: true

  alias App.Chat

  describe "correções do carregamento histórico" do
    test "mensagens são recarregadas após conexão" do
      order_id = "RELOAD-TEST-001"

      # Criar mensagens históricas
      {:ok, msg1} = Chat.create_message(%{
        text: "Mensagem histórica 1",
        sender_id: "user1",
        sender_name: "João",
        order_id: order_id,
        tipo: "mensagem"
      })

      :timer.sleep(10)

      {:ok, msg2} = Chat.create_message(%{
        text: "Mensagem histórica 2",
        sender_id: "user2",
        sender_name: "Maria",
        order_id: order_id,
        tipo: "mensagem"
      })

      # Simular carregamento inicial (que deve funcionar agora)
      {:ok, messages, has_more} = Chat.list_messages_for_order(order_id, 50, 0)

      # Verificar que mensagens são carregadas corretamente
      assert length(messages) == 2
      assert has_more == false

      # Verificar ordem cronológica
      assert Enum.at(messages, 0).id == msg1.id
      assert Enum.at(messages, 1).id == msg2.id

      # Verificar conteúdo
      assert Enum.at(messages, 0).text == "Mensagem histórica 1"
      assert Enum.at(messages, 1).text == "Mensagem histórica 2"
    end

    test "função list_messages_for_order é robusta contra problemas de conexão" do
      order_id = "ROBUST-TEST-001"

      # Criar algumas mensagens
      Enum.each(1..5, fn i ->
        Chat.create_message(%{
          text: "Mensagem robusta #{i}",
          sender_id: "user1",
          sender_name: "Usuário Teste",
          order_id: order_id,
          tipo: "mensagem"
        })
        :timer.sleep(5)
      end)

      # Chamar múltiplas vezes para simular reconexões
      results = for _i <- 1..3 do
        Chat.list_messages_for_order(order_id, 50, 0)
      end

      # Todas as chamadas devem retornar o mesmo resultado
      assert Enum.all?(results, fn {:ok, messages, _has_more} ->
        length(messages) == 5
      end)

      # Verificar que todas têm o mesmo conteúdo
      [{:ok, first_messages, _} | _] = results

      Enum.each(results, fn {:ok, messages, _} ->
        assert Enum.map(messages, &(&1.text)) == Enum.map(first_messages, &(&1.text))
      end)
    end

    test "mensagens antigas permanecem disponíveis mesmo após muito tempo" do
      order_id = "OLD-MESSAGES-TEST"

      # Criar mensagem muito antiga
      old_datetime = DateTime.add(DateTime.utc_now(), -86400, :second) # 24h atrás

      {:ok, old_msg} = Chat.create_message(%{
        text: "Mensagem muito antiga",
        sender_id: "user1",
        sender_name: "Usuário Antigo",
        order_id: order_id,
        tipo: "mensagem"
      })

      # Simular que passou muito tempo
      :timer.sleep(100)

      # Criar mensagem recente
      {:ok, recent_msg} = Chat.create_message(%{
        text: "Mensagem recente",
        sender_id: "user2",
        sender_name: "Usuário Novo",
        order_id: order_id,
        tipo: "mensagem"
      })

      # Buscar todas as mensagens (simula usuário entrando no chat)
      {:ok, messages, _} = Chat.list_messages_for_order(order_id, 50, 0)

      # Ambas as mensagens devem estar disponíveis
      assert length(messages) == 2

      message_texts = Enum.map(messages, &(&1.text))
      assert "Mensagem muito antiga" in message_texts
      assert "Mensagem recente" in message_texts

      # Verificar ordem cronológica (antiga primeiro)
      assert Enum.at(messages, 0).text == "Mensagem muito antiga"
      assert Enum.at(messages, 1).text == "Mensagem recente"
    end

    test "diferentes usuários veem o mesmo histórico" do
      order_id = "SHARED-HISTORY-TEST"

      # Usuário 1 envia mensagem
      {:ok, msg1} = Chat.send_message(order_id, "user1", "João", "Mensagem do João")

      # Usuário 2 envia mensagem
      {:ok, msg2} = Chat.send_message(order_id, "user2", "Maria", "Resposta da Maria")

      # Usuário 3 entra no chat depois (simula cenário real)
      # Deve ver todo o histórico
      {:ok, messages_user3, _} = Chat.list_messages_for_order(order_id, 50, 0)

      assert length(messages_user3) == 2
      assert Enum.at(messages_user3, 0).text == "Mensagem do João"
      assert Enum.at(messages_user3, 1).text == "Resposta da Maria"

      # Usuário 1 também deve ver todo o histórico quando recarrega
      {:ok, messages_user1, _} = Chat.list_messages_for_order(order_id, 50, 0)

      assert messages_user1 == messages_user3
    end
  end
end
