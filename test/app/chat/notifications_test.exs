defmodule App.Chat.NotificationsTest do
  @moduledoc """
  Testes para o sistema de notificações de chat.

  Testa funcionalidades como:
  - Notificações de som quando mensagens são lidas
  - Configurações de usuário para notificações
  - Debounce de notificações
  - Batching de emails
  """

  use App.DataCase
  alias App.Chat.Notifications

  describe "sound_notifications" do
    test "envia notificação de som quando mensagem é lida" do
      user_id = "user_123"
      message_id = "msg_456"
      reader_id = "reader_789"

      # Subscrever ao tópico de notificações de som
      Phoenix.PubSub.subscribe(App.PubSub, "sound_notifications:#{user_id}")

      # Simular mensagem sendo lida
      Notifications.notify_message_read(user_id, message_id, reader_id)

      # Verificar se recebeu notificação de som
      assert_receive {:play_read_sound, %{
        message_id: ^message_id,
        reader_id: ^reader_id,
        sound_type: "message_read"
      }}, 1000
    end

    test "não envia som se configuração de som estiver desabilitada" do
      user_id = "user_sound_off"
      message_id = "msg_123"
      reader_id = "reader_456"

      # Desabilitar som para o usuário
      {:ok, _} = Notifications.update_user_settings(user_id, %{sound_enabled: false})

      # Subscrever ao tópico
      Phoenix.PubSub.subscribe(App.PubSub, "sound_notifications:#{user_id}")

      # Simular mensagem sendo lida
      Notifications.notify_message_read(user_id, message_id, reader_id)

      # Não deve receber notificação de som
      refute_receive {:play_read_sound, _}, 500
    end

    test "aplica debounce em notificações rápidas" do
      user_id = "user_debounce"

      # Subscrever
      Phoenix.PubSub.subscribe(App.PubSub, "sound_notifications:#{user_id}")

      # Enviar múltiplas notificações rapidamente
      Notifications.notify_message_read(user_id, "msg_1", "reader_1")
      Notifications.notify_message_read(user_id, "msg_2", "reader_1")
      Notifications.notify_message_read(user_id, "msg_3", "reader_1")

      # Deve receber apenas uma notificação (debounced)
      assert_receive {:play_read_sound, _}, 1000
      refute_receive {:play_read_sound, _}, 100
    end
  end

  describe "bulk_read_notifications" do
    test "envia notificação especial para bulk read" do
      user_id = "user_bulk"
      order_id = "order_123"
      count = 5
      reader_id = "reader_456"

      # Subscrever
      Phoenix.PubSub.subscribe(App.PubSub, "sound_notifications:#{user_id}")

      # Notificar bulk read
      Notifications.notify_bulk_read(user_id, order_id, count, reader_id)

      # Verificar notificação especial
      assert_receive {:play_read_sound, %{
        sound_type: "bulk_read",
        count: ^count,
        reader_id: ^reader_id,
        order_id: ^order_id
      }}, 1000
    end

    test "usa som diferente para bulk read com muitas mensagens" do
      user_id = "user_many"
      order_id = "order_456"
      count = 15  # Mais de 10 mensagens
      reader_id = "reader_789"

      Phoenix.PubSub.subscribe(App.PubSub, "sound_notifications:#{user_id}")

      Notifications.notify_bulk_read(user_id, order_id, count, reader_id)

      assert_receive {:play_read_sound, %{
        sound_type: "bulk_read_many",
        count: ^count
      }}, 1000
    end
  end

  describe "user_settings" do
    test "cria configurações padrão para novo usuário" do
      user_id = "new_user_123"

      {:ok, settings} = Notifications.get_user_settings(user_id)

      assert settings.sound_enabled == true
      assert settings.desktop_enabled == true
      assert settings.email_enabled == true
      assert settings.read_confirmations_enabled == true
    end

    test "atualiza configurações existentes" do
      user_id = "existing_user"

      # Criar configurações iniciais
      {:ok, _} = Notifications.update_user_settings(user_id, %{
        sound_enabled: true,
        desktop_enabled: true
      })

      # Atualizar algumas configurações
      {:ok, updated} = Notifications.update_user_settings(user_id, %{
        sound_enabled: false,
        read_confirmations_enabled: false
      })

      assert updated.sound_enabled == false
      assert updated.desktop_enabled == true  # Mantido
      assert updated.read_confirmations_enabled == false
    end

    test "valida configurações inválidas" do
      user_id = "invalid_user"

      # Tentar configuração inválida
      {:error, changeset} = Notifications.update_user_settings(user_id, %{
        sound_enabled: "invalid",
        desktop_enabled: 123
      })

      assert changeset.errors[:sound_enabled]
      assert changeset.errors[:desktop_enabled]
    end
  end

  describe "statistics" do
    test "retorna estatísticas de notificações" do
      # Simular algumas notificações
      Notifications.notify_message_read("user_1", "msg_1", "reader_1")
      Notifications.notify_message_read("user_2", "msg_2", "reader_2")
      Notifications.notify_bulk_read("user_3", "order_1", 5, "reader_3")

      {:ok, stats} = Notifications.get_stats()

      assert stats.total_read_notifications >= 2
      assert stats.total_bulk_notifications >= 1
      assert stats.sounds_played >= 0
      assert is_integer(stats.debounced_count)
    end

    test "reseta estatísticas" do
      # Gerar algumas estatísticas
      Notifications.notify_message_read("user_stats", "msg_stats", "reader_stats")

      {:ok, _} = Notifications.reset_stats()

      {:ok, stats} = Notifications.get_stats()
      assert stats.total_read_notifications == 0
      assert stats.total_bulk_notifications == 0
    end
  end
end
