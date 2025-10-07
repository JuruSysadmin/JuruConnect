defmodule App.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Chat.Message
  alias App.Chat.MessageAttachment
  alias App.Chat.MessageReadReceipt

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
    case validate_message_content(text, file_info) do
      :ok -> create_and_send_message(treaty_id, sender_id, text, file_info)
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_message_content(text, file_info) do
    if String.trim(text) == "" and is_nil(file_info) do
      {:error, "Mensagem deve conter texto ou anexo"}
    else
      :ok
    end
  end

  defp create_and_send_message(treaty_id, sender_id, text, file_info) do
    sender_name = get_sender_name(sender_id)
    params = build_message_params(sender_id, sender_name, treaty_id, text)

    case create_message(params) do
      {:ok, message} -> process_successful_message(message, treaty_id, sender_id, file_info)
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp build_message_params(sender_id, sender_name, treaty_id, text) do
    %{
      text: text,
      sender_id: sender_id,
      sender_name: sender_name,
      treaty_id: treaty_id,
      tipo: "mensagem",
      timestamp: DateTime.utc_now()
    }
  end

  defp process_successful_message(message, treaty_id, sender_id, file_info) do
    process_file_uploads(file_info, treaty_id, sender_id, message.id)
    message_with_attachments = load_message_attachments(message)
    broadcast_message(message_with_attachments, treaty_id)
    process_message_notifications(message_with_attachments, treaty_id)
    {:ok, message_with_attachments}
  end

  defp process_file_uploads(nil, _treaty_id, _sender_id, _message_id), do: :ok
  defp process_file_uploads(file_info, treaty_id, sender_id, message_id) do
    files = normalize_file_info(file_info)
    Enum.each(files, &schedule_file_upload(&1, treaty_id, sender_id, message_id))
  end

  defp normalize_file_info(file_info) when is_list(file_info), do: file_info
  defp normalize_file_info(file_info), do: [file_info]

  defp schedule_file_upload(file, treaty_id, sender_id, message_id) do
    if file && file.pending_upload do
      job_args = build_upload_job_args(file, treaty_id, sender_id, message_id)
      App.Jobs.MediaProcessingJob.new(job_args) |> Oban.insert()
    end
  end

  defp build_upload_job_args(file, treaty_id, sender_id, message_id) do
    %{
      "file_path" => file.temp_path,
      "original_filename" => file.original_filename,
      "file_size" => file.file_size,
      "mime_type" => file.mime_type,
      "treaty_id" => treaty_id,
      "user_id" => sender_id,
      "message_id" => message_id
    }
  end

  defp load_message_attachments(message) do
    %{message | attachments: get_message_attachments(message.id)}
  end

  defp broadcast_message(message_with_attachments, treaty_id) do
    topic = "treaty:#{treaty_id}"
    Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message_with_attachments})
  end

  defp get_sender_name(nil), do: "Usuário Anônimo"
  defp get_sender_name(sender_id) when is_binary(sender_id) do
    try do
      case App.Accounts.get_user!(sender_id) do
        %{name: name} when not is_nil(name) -> name
        %{username: username} when not is_nil(username) -> username
        _ -> "Usuário"
      end
    rescue
      Ecto.NoResultsError -> "Usuário Removido"
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

  # === FUNCTIONS FOR READ RECEIPTS ===

  @doc """
  Marca uma mensagem como lida por um usuário.
  """
  def mark_message_as_read(message_id, user_id, treaty_id) when is_binary(message_id) and is_binary(user_id) and is_binary(treaty_id) do
    %MessageReadReceipt{}
    |> MessageReadReceipt.create_changeset(%{
      message_id: message_id,
      user_id: user_id,
      treaty_id: treaty_id
    })
    |> Repo.insert()
  end

  @doc """
  Obtém todas as confirmações de leitura para uma mensagem.
  """
  def get_message_read_receipts(message_id) when is_binary(message_id) do
    MessageReadReceipt
    |> where([rr], rr.message_id == ^message_id)
    |> join(:inner, [rr], u in "users", on: rr.user_id == u.id)
    |> select([rr, u], %{
      user_id: rr.user_id,
      user_name: u.name,
      username: u.username,
      read_at: rr.read_at
    })
    |> Repo.all()
  end

  @doc """
  Obtém confirmações de leitura para múltiplas mensagens de uma tratativa.
  Recebe uma lista de message_ids e retorna um mapa: %{message_id => [receipts]}
  """
  def get_read_receipts_for_messages(message_ids, treaty_id) when is_list(message_ids) and is_binary(treaty_id) do
    if Enum.empty?(message_ids) do
      %{}
    else
      MessageReadReceipt
      |> where([rr], rr.message_id in ^message_ids and rr.treaty_id == ^treaty_id)
      |> join(:inner, [rr], u in "users", on: rr.user_id == u.id)
      |> select([rr, u], %{
        message_id: rr.message_id,
        user_id: rr.user_id,
        user_name: u.name,
        username: u.username,
        read_at: rr.read_at
      })
      |> Repo.all()
      |> Enum.group_by(& &1.message_id, fn receipt ->
        Map.delete(receipt, :message_id)
      end)
    end
  end

  @doc """
  Verifica se um usuário já leu uma mensagem específica.
  """
  def user_has_read_message?(message_id, user_id) when is_binary(message_id) and is_binary(user_id) do
    MessageReadReceipt
    |> where([rr], rr.message_id == ^message_id and rr.user_id == ^user_id)
    |> Repo.exists?()
  end

  @doc """
  Obtém estatísticas de leitura para uma tratativa:
  - Total de mensagens
  - Mensagens lidas por usuário
  - Taxa de leitura geral
  """
  def get_treaty_read_stats(treaty_id) when is_binary(treaty_id) do
    # Total de mensagens na tratativa
    total_messages = Message
    |> where([m], m.treaty_id == ^treaty_id)
    |> Repo.aggregate(:count, :id)

    # Confirmações de leitura por usuário
    read_stats = MessageReadReceipt
    |> where([rr], rr.treaty_id == ^treaty_id)
    |> join(:inner, [rr], u in "users", on: rr.user_id == u.id)
    |> group_by([rr, u], [rr.user_id, u.name, u.username])
    |> select([rr, u], %{
      user_id: rr.user_id,
      user_name: u.name,
      username: u.username,
      messages_read: count(rr.message_id)
    })
    |> Repo.all()

    %{
      total_messages: total_messages,
      read_stats: read_stats,
      reading_percentages: calculate_reading_percentages(read_stats, total_messages)
    }
  end

  defp calculate_reading_percentages(read_stats, total_messages) do
    if total_messages > 0 do
      Enum.map(read_stats, fn stat ->
        Map.put(stat, :percentage_read, round(stat.messages_read / total_messages * 100))
      end)
    else
      Enum.map(read_stats, fn stat ->
        Map.put(stat, :percentage_read, 0)
      end)
    end
  end
end
