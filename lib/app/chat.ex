defmodule App.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false
  alias App.Chat.Message
  alias App.Repo

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

  def user_has_access?(_user_id, _chat_id), do: true

  def list_messages(chat_id, opts \\ []) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 50)

    query =
      from(m in Message,
        where: m.chat_id == ^chat_id,
        order_by: [desc: m.inserted_at],
        offset: ^offset,
        limit: ^limit
      )

    messages = Repo.all(query) |> Enum.reverse()

    has_more_messages = length(messages) == limit
    {:ok, messages, has_more_messages}
  end



  def get_messages(chat_id) do
    # Implementação corrigida para buscar mensagens por chat_id
    case list_recent_messages(chat_id) do
      messages when is_list(messages) -> {:ok, messages}
      _ -> {:error, :not_found}
    end
  end

  def list_messages_for_order(order_id, limit \\ 50, offset \\ 0) do
    query =
      from(m in Message,
        where: m.order_id == ^order_id,
        order_by: [asc: m.inserted_at],
        offset: ^offset,
        limit: ^limit
      )

    messages = Repo.all(query)
    has_more_messages = length(messages) == limit
    {:ok, messages, has_more_messages}
  end

  def list_messages_until(order_id, last_message_id) do
    query =
      from(m in Message,
        where: m.order_id == ^order_id and m.id <= ^last_message_id,
        order_by: [asc: m.inserted_at]
      )

    messages = Repo.all(query)
    {:ok, messages}
  end

  def count_unread_messages(user_id, order_id) do
    # Implementação simplificada - contar todas as mensagens do pedido que não são do usuário
    query =
      from(m in Message,
        where: m.order_id == ^order_id and m.sender_id != ^user_id,
        select: count(m.id)
      )

    count = Repo.one(query) || 0
    {:ok, count}
  end

  def get_message_read_stats(order_id) do
    total_query =
      from(m in Message,
        where: m.order_id == ^order_id,
        select: count(m.id)
      )

    total = Repo.one(total_query) || 0

    stats = %{
      total: total,
      read: 0,  # Implementar quando tiver tabela de status
      unread: total
    }

    {:ok, stats}
  end

  def send_message(order_id, sender_id, sender_name, text, image_url \\ nil) do
    params = %{
      text: text,
      sender_id: sender_id,
      sender_name: sender_name,
      order_id: order_id,
      tipo: "mensagem",
      image_url: image_url,
      status: "sent"
    }

    case create_message(params) do
      {:ok, message} ->
        # Publicar a mensagem via PubSub
        topic = "order:#{order_id}"
        Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message})
        {:ok, message}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Marca uma mensagem como entregue para um usuário específico
  """
  def mark_message_delivered(message_id, user_id) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      message ->
        delivered_to = message.delivered_to || []

        if user_id in delivered_to do
          {:ok, message}
        else
          changeset = Message.changeset(message, %{
            delivered_to: [user_id | delivered_to],
            delivered_at: DateTime.utc_now(),
            status: get_message_status(message, [user_id | delivered_to], message.read_by || [])
          })

          case Repo.update(changeset) do
            {:ok, updated_message} ->
              # Broadcast status update
              topic = "order:#{updated_message.order_id}"
              Phoenix.PubSub.broadcast(App.PubSub, topic,
                {:message_status_update, updated_message.id, :delivered, user_id})
              {:ok, updated_message}

            {:error, changeset} ->
              {:error, changeset}
          end
        end
    end
  end

  @doc """
  Marca uma mensagem como lida por um usuário específico
  """
  def mark_message_read(message_id, user_id) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      message ->
        read_by = message.read_by || []

        if user_id in read_by do
          {:ok, message}
        else
          changeset = Message.changeset(message, %{
            read_by: [user_id | read_by],
            read_at: DateTime.utc_now(),
            status: get_message_status(message, message.delivered_to || [], [user_id | read_by])
          })

                    case Repo.update(changeset) do
            {:ok, updated_message} ->
              # Broadcast status update
              topic = "order:#{updated_message.order_id}"
              Phoenix.PubSub.broadcast(App.PubSub, topic,
                {:message_status_update, updated_message.id, :read, user_id})

              # Enviar notificação de leitura para o remetente
              Phoenix.PubSub.broadcast(App.PubSub, "notifications:#{updated_message.sender_id}",
                {:message_read_notification, %{
                  message_id: updated_message.id,
                  reader_id: user_id,
                  sender_id: updated_message.sender_id
                }})

              {:ok, updated_message}

            {:error, changeset} ->
              {:error, changeset}
          end
        end
    end
  end

  @doc """
  Marca todas as mensagens visíveis como entregues para um usuário
  """
  def mark_all_messages_delivered(order_id, user_id) do
    query =
      from(m in Message,
        where: m.order_id == ^order_id and m.sender_id != ^user_id,
        where: not(^user_id in m.delivered_to)
      )

    messages = Repo.all(query)

    Enum.each(messages, fn message ->
      mark_message_delivered(message.id, user_id)
    end)

    {:ok, length(messages)}
  end

  @doc """
  Marca todas as mensagens visíveis como lidas para um usuário
  """
  def mark_all_messages_read(order_id, user_id) do
    query =
      from(m in Message,
        where: m.order_id == ^order_id and m.sender_id != ^user_id,
        where: not(^user_id in m.read_by)
      )

    messages = Repo.all(query)

    Enum.each(messages, fn message ->
      mark_message_read(message.id, user_id)
    end)

    {:ok, length(messages)}
  end

  @doc """
  Marca múltiplas mensagens como lidas em lote para um usuário.

  Esta função é otimizada para processar muitas mensagens de uma vez,
  enviando notificações em lote e usando transações de banco de dados.
  """
  def bulk_mark_messages_read(order_id, user_id) do
    query =
      from(m in Message,
        where: m.order_id == ^order_id and m.sender_id != ^user_id,
        where: not(^user_id in m.read_by)
      )

    messages = Repo.all(query)

    case messages do
      [] ->
        {:ok, 0}

      _ ->
        Repo.transaction(fn ->
          count = Enum.reduce(messages, 0, fn message, acc ->
            case mark_message_read(message.id, user_id) do
              {:ok, _} -> acc + 1
              {:error, _} -> acc
            end
          end)

          # Enviar notificação de bulk read
          if count > 0 do
            senders = messages |> Enum.map(& &1.sender_id) |> Enum.uniq()

            Enum.each(senders, fn sender_id ->
              sender_messages_count =
                messages
                |> Enum.filter(fn msg -> msg.sender_id == sender_id end)
                |> length()

              Phoenix.PubSub.broadcast(App.PubSub, "notifications:#{sender_id}",
                {:bulk_read_notification, %{
                  count: sender_messages_count,
                  reader_id: user_id,
                  sender_id: sender_id,
                  order_id: order_id
                }})
            end)
          end

          count
        end)
        |> case do
          {:ok, count} -> {:ok, count}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Obtém a contagem de mensagens não lidas para um usuário em um pedido específico
  """
  def get_unread_count(order_id, user_id) do
    query =
      from(m in Message,
        where: m.order_id == ^order_id and m.sender_id != ^user_id,
        where: not(^user_id in m.read_by),
        select: count(m.id)
      )

    count = Repo.one(query) || 0
    {:ok, count}
  end

  @doc """
  Obtém uma mensagem pelo ID
  """
  def get_message!(id) do
    Repo.get!(Message, id)
  end

  @doc """
  Busca mensagens onde um usuário específico foi mencionado.

  ## Parâmetros
  - order_id: ID do pedido
  - username: Nome do usuário mencionado

  ## Retorna
  Lista de mensagens onde o usuário foi mencionado, ordenadas por data.
  """
  def get_mentions_for_user(order_id, username) do
    query = from(m in Message,
      where: m.order_id == ^order_id and m.has_mentions == true,
      where: ^username in m.mentions,
      order_by: [desc: m.inserted_at]
    )

    Repo.all(query)
  end

  @doc """
  Busca todas as mensagens de uma thread (mensagem original + suas respostas).

  ## Parâmetros
  - message_id: ID da mensagem original ou de uma resposta na thread

  ## Retorna
  Lista com a mensagem original e todas as suas respostas, ordenadas por data.
  """
  def get_thread_messages(message_id) do
    # Primeiro, encontrar a mensagem raiz da thread
    root_message = case Repo.get(Message, message_id) do
      %Message{reply_to: nil} = msg -> msg
      %Message{reply_to: root_id} -> Repo.get!(Message, root_id)
      nil -> nil
    end

    case root_message do
      nil -> []
      root ->
        # Buscar mensagem raiz + todas as respostas
        query = from(m in Message,
          where: m.id == ^root.id or m.reply_to == ^root.id,
          order_by: [asc: m.inserted_at]
        )

        Repo.all(query)
    end
  end

  @doc """
  Envia notificações para usuários mencionados em uma mensagem.

  ## Parâmetros
  - message: Struct da mensagem contendo as menções
  """
  def send_mention_notifications(%Message{has_mentions: false}), do: :ok

  def send_mention_notifications(%Message{has_mentions: true, mentions: mentions} = message) do
    # Buscar IDs dos usuários mencionados
    mentioned_users = App.Accounts.get_users_by_usernames(mentions)

    Enum.each(mentioned_users, fn user ->
      # Enviar notificação via PubSub
      Phoenix.PubSub.broadcast(App.PubSub, "mentions:#{user.id}",
        {:mention_notification, %{
          message_id: message.id,
          mentioned_user: user.username,
          sender_id: message.sender_id,
          sender_name: message.sender_name,
          order_id: message.order_id,
          text: message.text
        }})
    end)

    :ok
  end

  @doc """
  Cria uma mensagem com processamento automático de menções e resposta.

  Sobrescreve a função create_message original para incluir processamento de menções.
  """
  def create_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        # Enviar notificações de menção
        send_mention_notifications(message)
        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Conta mensagens não lidas que mencionam um usuário específico.

  ## Parâmetros
  - order_id: ID do pedido
  - username: Nome do usuário

  ## Retorna
  {:ok, count} onde count é o número de menções não lidas.
  """
  def get_unread_mentions_count(order_id, username) do
    query = from(m in Message,
      where: m.order_id == ^order_id and m.has_mentions == true,
      where: ^username in m.mentions,
      where: not(^username in m.read_by),
      select: count(m.id)
    )

    count = Repo.one(query) || 0
    {:ok, count}
  end

  @doc """
  Busca mensagens de uma thread com informações de contexto.

  ## Parâmetros
  - message_id: ID da mensagem
  - limit: Número máximo de mensagens de contexto (padrão: 50)

  ## Retorna
  Tupla {original_message, replies} onde:
  - original_message: A mensagem raiz da thread
  - replies: Lista de respostas à mensagem original
  """
  def get_thread_with_context(message_id, limit \\ 50) do
    case get_thread_messages(message_id) do
      [] -> {nil, []}
      [original | replies] -> {original, Enum.take(replies, limit)}
    end
  end

  @doc """
  Marca mensagens com menções como lidas para um usuário.

  ## Parâmetros
  - order_id: ID do pedido
  - username: Nome do usuário

  ## Retorna
  {:ok, count} onde count é o número de menções marcadas como lidas.
  """
  def mark_mentions_read(order_id, username) do
    query = from(m in Message,
      where: m.order_id == ^order_id and m.has_mentions == true,
      where: ^username in m.mentions,
      where: not(^username in m.read_by)
    )

    messages = Repo.all(query)

    case messages do
      [] ->
        {:ok, 0}

      _ ->
        Enum.reduce(messages, {:ok, 0}, fn message, {:ok, acc} ->
          case mark_message_read(message.id, username) do
            {:ok, _} -> {:ok, acc + 1}
            error -> error
          end
        end)
    end
  end

  # Função auxiliar para determinar o status geral da mensagem
  defp get_message_status(_message, delivered_to, read_by) do
    cond do
      length(read_by) > 0 -> "read"
      length(delivered_to) > 0 -> "delivered"
      true -> "sent"
    end
  end
end
