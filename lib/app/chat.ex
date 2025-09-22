defmodule App.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Chat.Message
  alias App.ChatSession
  require Logger

  def list_recent_messages(chat_id, limit \\ 100) do
    from(m in Message,
      where: m.chat_id == ^chat_id,
      order_by: [asc: m.inserted_at],
      limit: ^limit,
      select: %{
        id: m.id,
        text: m.text,
        sender: m.sender,
        tipo: m.tipo,
        timestamp: m.inserted_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Verifies if a user has access to a specific chat.
  TODO: Implement real access logic based on your application's rules.
  """
  def user_has_access?(_user_id, _chat_id), do: true

  @doc """
  Lists messages for a given chat, with pagination.
  """
  def list_messages(chat_id, opts \\ []) when is_binary(chat_id) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 50)

    Message
    |> where([m], m.chat_id == ^chat_id)
    |> order_by([m], desc: m.inserted_at)
    |> offset(^offset)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
    |> then(fn messages ->
      has_more_messages = length(messages) == limit
      {:ok, messages, has_more_messages}
    end)
  end

  @doc """
  Creates and persists a new message.
  """
  def create_message(params) do
    %Message{}
    |> Message.changeset(params)
    |> Repo.insert()
  end

  def get_messages(chat_id) do
    list_recent_messages(chat_id)
  end

  @doc """
  Lista mensagens para um pedido (order_id), com limite e offset opcional.
  """
  def list_messages_for_order(order_id, limit \\ 50, offset \\ 0)
      when is_binary(order_id) and is_integer(limit) and is_integer(offset) do
    Message
    |> where([m], m.order_id == ^order_id)
    |> order_by([m], asc: m.timestamp)
    |> offset(^offset)
    |> limit(^limit)
    |> Repo.all()
    |> then(fn messages ->
      has_more_messages = length(messages) == limit
      {:ok, messages, has_more_messages}
    end)
  end

  @doc """
  Envia uma mensagem para um pedido específico, com suporte a imagem e notificações.
  """
  def send_message(order_id, sender_id, text, image_url \\ nil)
      when is_binary(order_id) and is_binary(text) and byte_size(text) > 0 do
    sender_name = get_sender_name(sender_id)

    params = %{
      text: text,
      sender_id: sender_id,
      sender_name: sender_name,
      order_id: order_id,
      tipo: "mensagem",
      image_url: image_url,
      timestamp: DateTime.utc_now()
    }

    case create_message(params) do
      {:ok, message} ->
        # Publicar a mensagem via PubSub
        topic = "order:#{order_id}"
        Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message})

        # Processar notificações
        process_message_notifications(message, order_id)

        {:ok, message}
      {:error, changeset} ->
        Logger.error("Erro ao criar mensagem: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp get_sender_name(nil), do: "Usuário Anônimo"
  defp get_sender_name(sender_id) when is_binary(sender_id) do
    case App.Accounts.get_user!(sender_id) do
      %{name: name} when not is_nil(name) -> name
      %{username: username} when not is_nil(username) -> username
      _ -> "Usuário"
    end
  end
  defp get_sender_name(_), do: "Usuário"

  defp process_message_notifications(message, order_id) do
    # Buscar todos os usuários que têm acesso ao pedido
    # Por enquanto, vamos notificar todos os usuários online no chat
    topic = "order:#{order_id}"
    presences = AppWeb.Presence.list(topic)

    # Extrair IDs dos usuários online
    online_user_ids = presences
    |> Map.values()
    |> Enum.flat_map(fn %{metas: metas} ->
      Enum.map(metas, fn %{user_id: user_id} -> user_id end)
    end)
    |> Enum.filter(&(&1 != "anonymous" && &1 != nil))
    |> Enum.uniq()

    # Enviar notificações para usuários online
    Enum.each(online_user_ids, fn user_id ->
      App.Notifications.notify_new_message(message, user_id)
    end)

    # Verificar menções na mensagem
    mentioned_users = App.Notifications.extract_mentions(message.text)
    if length(mentioned_users) > 0 do
      App.Notifications.notify_mention(message, mentioned_users)
    end
  end
end
