defmodule App.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false
  alias App.Chat.Message
  alias App.ChatSession
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

  def create_message(params) do
    %Message{}
    |> Message.changeset(params)
    |> Repo.insert()
  end

  def get_messages(chat_id) do
    ChatSession.get_messages(chat_id)
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

  def send_message(order_id, sender_id, text, image_url \\ nil) do
    params = %{
      text: text,
      sender_id: sender_id,
      # Usando sender_id como sender_name por enquanto
      sender_name: sender_id,
      order_id: order_id,
      tipo: "mensagem",
      image_url: image_url
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
end
