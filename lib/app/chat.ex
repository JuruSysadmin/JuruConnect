defmodule App.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Chat.Message
  alias App.Chat.MessageAttachment

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
  Lista mensagens para uma tratativa (treaty_id), com limite e offset opcional.
  """
  def list_messages_for_treaty(treaty_id, limit \\ 50, offset \\ 0)
      when is_binary(treaty_id) and is_integer(limit) and is_integer(offset) do
    messages = Message
    |> where([m], m.treaty_id == ^treaty_id)
    |> order_by([m], asc: m.timestamp)
    |> offset(^offset)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn message ->
      attachments = get_message_attachments(message.id)
      %{message | attachments: attachments}
    end)

    has_more_messages = length(messages) == limit
    {:ok, messages, has_more_messages}
  end

  @doc """
  Envia uma mensagem para uma tratativa específica, com suporte a anexos e notificações.
  """
  def send_message(treaty_id, sender_id, text, file_info \\ nil)
      when is_binary(treaty_id) and is_binary(text) do
    # Validar que a mensagem tenha conteúdo (texto ou anexo)
    if String.trim(text) == "" and is_nil(file_info) do
      {:error, "Mensagem deve conter texto ou anexo"}
    else
      sender_name = get_sender_name(sender_id)

      params = %{
        text: text,
        sender_id: sender_id,
        sender_name: sender_name,
        treaty_id: treaty_id,
        tipo: "mensagem",
        timestamp: DateTime.utc_now()
      }

    case create_message(params) do
      {:ok, message} ->
        # Criar anexo se houver arquivo
        if file_info do
          case create_image_attachment(message.id, sender_id, file_info) do
            {:ok, _attachment} ->
              :ok
            {:error, _changeset} ->
              :ok
          end
        end

        # Carregar anexos para a mensagem
        message_with_attachments = %{message | attachments: get_message_attachments(message.id)}

        # Publicar a mensagem via PubSub
        topic = "treaty:#{treaty_id}"
        Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message_with_attachments})

        # Processar notificações
        process_message_notifications(message_with_attachments, treaty_id)

        {:ok, message_with_attachments}
      {:error, changeset} ->
        {:error, changeset}
    end
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

  defp process_message_notifications(message, treaty_id) do
    # Buscar todos os usuários que têm acesso à tratativa
    # Por enquanto, vamos notificar todos os usuários online no chat
    topic = "treaty:#{treaty_id}"
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

  # Message Attachments functions

  @doc """
  Creates a message attachment.
  """
  def create_message_attachment(attrs \\ %{}) do
    %MessageAttachment{}
    |> MessageAttachment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an image attachment for a message.
  """
  def create_image_attachment(message_id, uploaded_by_id, file_info) do
    %{
      message_id: message_id,
      uploaded_by_id: uploaded_by_id,
      filename: file_info.filename,
      original_filename: file_info.original_filename,
      file_size: file_info.file_size,
      mime_type: file_info.mime_type,
      file_url: file_info.file_url,
      file_type: "image"
    }
    |> create_message_attachment()
  end

  @doc """
  Gets all attachments for a message.
  """
  def get_message_attachments(message_id) do
    from(ma in MessageAttachment,
      where: ma.message_id == ^message_id,
      order_by: [asc: ma.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets image attachments for a message.
  """
  def get_message_images(message_id) do
    from(ma in MessageAttachment,
      where: ma.message_id == ^message_id and ma.file_type == "image",
      order_by: [asc: ma.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Deletes a message attachment.
  """
  def delete_message_attachment(%MessageAttachment{} = attachment) do
    Repo.delete(attachment)
  end

  @doc """
  Deletes all attachments for a message.
  """
  def delete_message_attachments(message_id) do
    from(ma in MessageAttachment, where: ma.message_id == ^message_id)
    |> Repo.delete_all()
  end
end
