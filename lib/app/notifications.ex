defmodule App.Notifications do
  @moduledoc """
  Módulo para gerenciar notificações do sistema de chat.
  """

  alias App.Accounts
  alias App.Chat
  require Logger

  @doc """
  Envia notificação quando uma nova mensagem é recebida.
  """
  def notify_new_message(message, current_user_id) do
    # Verificar se a mensagem não é do usuário atual
    if message.sender_id != current_user_id do
      # Buscar informações do usuário atual
      case Accounts.get_user!(current_user_id) do
        nil ->
          Logger.warning("Usuário não encontrado para notificação: #{current_user_id}")
          :ok

        user ->
          # Verificar se o usuário está online no chat
          topic = "order:#{message.order_id}"
          presences = AppWeb.Presence.list(topic)

          user_online = presences
          |> Map.values()
          |> Enum.flat_map(fn %{metas: metas} ->
            Enum.map(metas, fn %{user_id: user_id} -> user_id end)
          end)
          |> Enum.member?(current_user_id)

          if user_online do
            # Usuário está online - enviar notificação via LiveView
            Phoenix.PubSub.broadcast(
              App.PubSub,
              "user:#{current_user_id}",
              {:notification, :new_message, %{
                message: message,
                order_id: message.order_id,
                sender_name: message.sender_name,
                text: message.text,
                timestamp: message.inserted_at
              }}
            )
          else
            # Usuário offline - salvar notificação para quando voltar
            save_offline_notification(current_user_id, message)
          end

          # Enviar notificação desktop se habilitada
          send_desktop_notification(user, message)
      end
    end
  end

  @doc """
  Envia notificação quando um usuário é mencionado (@username).
  """
  def notify_mention(message, mentioned_users) do
    Enum.each(mentioned_users, fn user_id ->
      case Accounts.get_user!(user_id) do
        nil ->
          Logger.warning("Usuário mencionado não encontrado: #{user_id}")

        user ->
          # Enviar notificação de menção
          Phoenix.PubSub.broadcast(
            App.PubSub,
            "user:#{user_id}",
            {:notification, :mention, %{
              message: message,
              order_id: message.order_id,
              sender_name: message.sender_name,
              text: message.text,
              timestamp: message.inserted_at,
              mentioned_by: message.sender_name
            }}
          )

          # Enviar notificação desktop
          send_desktop_notification(user, message, :mention)
      end
    end)
  end

  @doc """
  Busca notificações não lidas de um usuário.
  """
  def get_unread_notifications(user_id) do
    # Implementar busca de notificações não lidas
    # Por enquanto, retorna lista vazia
    []
  end

  @doc """
  Marca notificações como lidas.
  """
  def mark_notifications_as_read(user_id, notification_ids) do
    # Implementar marcação de notificações como lidas
    :ok
  end

  @doc """
  Extrai menções (@username) de uma mensagem.
  """
  def extract_mentions(text) do
    # Regex para encontrar @username
    regex = ~r/@(\w+)/

    case Regex.scan(regex, text) do
      [] -> []
      matches ->
        usernames = matches
        |> Enum.map(fn [_, username] -> username end)
        |> Enum.uniq()

        # Buscar IDs dos usuários mencionados
        usernames
        |> Enum.map(fn username ->
          case Accounts.get_user_by_username(username) do
            nil -> nil
            user -> user.id
          end
        end)
        |> Enum.filter(&(&1 != nil))
    end
  end

  @doc """
  Envia notificação desktop via JavaScript.
  """
  def send_desktop_notification(user, message, type \\ :new_message) do
    notification_config = App.ChatConfig.notification_config()

    if notification_config[:enable_desktop_notifications] do
      title = case type do
        :mention -> "Você foi mencionado!"
        _ -> "Nova mensagem"
      end

      body = case type do
        :mention -> "#{message.sender_name} mencionou você: #{String.slice(message.text, 0, 50)}"
        _ -> "#{message.sender_name}: #{String.slice(message.text, 0, 50)}"
      end

      # Enviar evento para o frontend
      Phoenix.PubSub.broadcast(
        App.PubSub,
        "user:#{user.id}",
        {:desktop_notification, %{
          title: title,
          body: body,
          icon: "/images/notification-icon.svg",
          tag: "chat-notification",
          data: %{
            order_id: message.order_id,
            message_id: message.id
          }
        }}
      )
    end
  end

  @doc """
  Salva notificação para usuário offline.
  """
  defp save_offline_notification(user_id, message) do
    # Implementar salvamento de notificação para usuário offline
    # Pode ser armazenado no banco de dados ou cache
    Logger.info("Salvando notificação offline para usuário #{user_id}")
    :ok
  end
end
