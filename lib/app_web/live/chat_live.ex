defmodule AppWeb.ChatLive do
  use AppWeb, :live_view
  alias App.ChatConfig
  alias AppWeb.Presence

    @impl true
  def mount(%{"order_id" => order_id}, _session, socket) do
    {:ok, initialize_chat_socket(socket, order_id)}
  end

  @impl true
  def handle_event("send_message", %{"message" => text}, socket) do
    trimmed_text = String.trim(text)

    # Evento send_message recebido

    cond do
      trimmed_text == "" and Enum.empty?(socket.assigns.uploads.image.entries) ->
        {:noreply, put_flash(socket, :error, "Mensagem não pode estar vazia")}

      String.length(trimmed_text) > ChatConfig.security_config()[:max_message_length] ->
        {:noreply, put_flash(socket, :error, "Mensagem muito longa")}

      true ->
        image_url = process_image_upload(socket)
        send_chat_message(socket, trimmed_text, image_url)
    end
  end

  @impl true
  def handle_event("load_older_messages", _params, socket) do
    if socket.assigns.loading_messages do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:loading_messages, true)
       |> load_older_messages_async()}
    end
  end

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :message_error, nil)}
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :message, message)}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  @impl true
  def handle_event("show_image", %{"url" => url}, socket) do
    {:noreply, assign(socket, :modal_image_url, url)}
  end

  @impl true
  def handle_event("close_image_modal", _params, socket) do
    {:noreply, assign(socket, :modal_image_url, nil)}
  end

  @impl true
  def handle_info({:new_message, msg}, socket) do
    # Verificar se a mensagem é para este pedido
    if msg.order_id == socket.assigns.order_id do
      {:noreply,
       socket
       |> update(:messages, fn msgs -> msgs ++ [msg] end)
       |> push_event("scroll-to-bottom", %{})
       |> push_event("play-notification-sound", %{})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:older_messages_loaded, older_messages, has_more}, socket) do
    {:noreply,
     socket
     |> assign(:messages, older_messages ++ socket.assigns.messages)
     |> assign(:has_more_messages, has_more)
     |> assign(:loading_messages, false)}
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: _diff}, socket) do
    presences = Presence.list(socket.assigns.topic)
    users_online = extract_users_from_presences(presences)

    # Log presence changes
    # Presence diff processing

    {:noreply,
     socket
     |> assign(:presences, presences)
     |> assign(:users_online, users_online)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="chat-container"
      class="h-screen w-screen bg-gray-50 font-sans antialiased flex"
      phx-hook="ChatHook"
      role="main"
    >
      <!-- Sidebar -->
      <aside
        class="w-80 lg:w-96 bg-white border-r border-gray-200 flex flex-col shadow-xl z-20 flex-shrink-0"
        role="complementary"
        aria-label="Informações do pedido e usuários online"
      >

    <!-- Header com logo/nome -->
        <header class="p-6 border-b border-gray-100 bg-gradient-to-r from-blue-50 via-indigo-50 to-purple-50">
          <div class="flex items-center space-x-3">
            <div class="w-10 h-10 bg-gradient-to-br from-blue-500 to-purple-600 rounded-xl flex items-center justify-center shadow-lg">
            </div>
            <div>
              <h1 class="text-2xl font-bold text-gray-900 tracking-tight">JuruConnect</h1>
              <p class="text-sm text-gray-600 mt-0.5 font-medium">Chat por Pedido</p>
            </div>
          </div>
        </header>

    <!-- Pedido Info Card -->
        <section class="p-6" aria-labelledby="order-info-title">
          <h2 id="order-info-title" class="sr-only">Informações do Pedido</h2>
          <div class="bg-gradient-to-br from-blue-50 via-indigo-50 to-purple-50 rounded-3xl p-6 border border-blue-100 shadow-sm hover:shadow-md transition-shadow duration-300">
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center space-x-2">
                <h3 class="text-lg font-bold text-gray-900">
                  Pedido #{@order["orderId"]}
                </h3>
              </div>
              <span class={get_status_class(@order["status"])}>
                {@order["status"]}
              </span>
            </div>

            <dl class="space-y-3 text-sm">
              <div class="flex justify-between items-center py-1">
                <dt class="text-gray-600 font-medium flex items-center">
                  Cliente:
                </dt>
                <dd
                  class="font-semibold text-gray-900 truncate ml-2 max-w-32"
                  title={@order["customerName"]}
                >
                  {@order["customerName"]}
                </dd>
              </div>
              <div class="flex justify-between items-center py-1">
                <dt class="text-gray-600 font-medium flex items-center">
                  Valor:
                </dt>
                <dd class="font-bold text-green-700 text-base">
                  R$ {format_currency(@order["amount"])}
                </dd>
              </div>
              <div class="flex justify-between items-center py-1">
                <dt class="text-gray-600 font-medium flex items-center">
                  Entrega:
                </dt>
                <dd class="font-semibold text-gray-900">{@order["deliveryType"]}</dd>
              </div>
              <div class="flex justify-between items-center py-1">
                <dt class="text-gray-600 font-medium flex items-center">
                  Data:
                </dt>
                <dd class="font-semibold text-gray-900">{format_date(@order["deliveryDate"])}</dd>
              </div>
            </dl>
          </div>
        </section>

    <!-- Usuários Online -->
        <section class="px-6 mb-6 flex-1" aria-labelledby="users-online-title">
          <h2 id="users-online-title" class="text-sm font-bold text-gray-800 mb-4 flex items-center">
            <div
              class="w-2.5 h-2.5 bg-green-500 rounded-full mr-3 animate-pulse shadow-sm"
              aria-hidden="true"
            >
            </div>
            Usuários Online ({length(@users_online)})
          </h2>

          <div class="space-y-2 max-h-64 overflow-y-auto" role="list">
            <%= if Enum.empty?(@users_online) do %>
              <div class="text-center py-8">
                <p class="text-sm text-gray-500 italic">Nenhum usuário online</p>
              </div>
            <% else %>
              <%= for user <- @users_online do %>
                <div
                  class="flex items-center p-3 rounded-xl hover:bg-gray-50 transition-all duration-200 border border-transparent hover:border-gray-200 hover:shadow-sm group"
                  role="listitem"
                >
                  <div
                    class="w-10 h-10 bg-gradient-to-br from-blue-500 to-purple-600 rounded-full flex items-center justify-center mr-3 shadow-md group-hover:shadow-lg transition-shadow duration-200"
                    aria-hidden="true"
                  >
                    <span class="text-white text-sm font-bold">{get_user_initial(user)}</span>
                  </div>
                  <div class="flex-1 min-w-0">
                    <span class="text-sm font-semibold text-gray-800 truncate block">{user}</span>
                    <%= if user == @current_user do %>
                      <span class="text-xs text-blue-600 font-medium">(Você)</span>
                    <% end %>
                  </div>
                  <div
                    class="w-2 h-2 bg-green-400 rounded-full flex-shrink-0 animate-pulse"
                    aria-label="Online"
                    title="Online"
                  >
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </section>

    <!-- Footer com informações do usuário atual -->
        <footer class="p-6 border-t border-gray-100 bg-gray-50/50">
          <div class="flex items-center justify-between">
            <div class="flex items-center flex-1 min-w-0">
              <div
                class="w-10 h-10 bg-gradient-to-br from-gray-500 to-gray-700 rounded-full flex items-center justify-center mr-3 shadow-md"
                aria-hidden="true"
              >
                <span class="text-white text-sm font-bold">{get_user_initial(@current_user)}</span>
              </div>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-semibold text-gray-900 truncate">{@current_user}</p>
                <p class="text-xs font-medium flex items-center">
                  <span class={get_connection_indicator_class(@connected)} aria-hidden="true"></span>
                  <span class={get_connection_text_class(@connected)}>{@connection_status}</span>
                </p>
              </div>
            </div>
            <button
              class="p-2.5 text-gray-500 hover:text-gray-700 hover:bg-gray-100 transition-all duration-200 rounded-lg hover:shadow-sm"
              aria-label="Configurações"
              title="Configurações"
            >
            </button>
          </div>
        </footer>
      </aside>

    <!-- Área principal do chat - colada na sidebar -->
      <main
        class="flex-1 h-screen flex flex-col bg-white min-w-0 border-l border-gray-100"
        role="main"
        aria-label="Área de chat"
      >
        <!-- Header do Chat -->
        <header class="flex items-center justify-between p-6 border-b border-gray-200 bg-white/95 backdrop-blur-sm flex-shrink-0 shadow-sm">
          <div class="flex items-center">
            <div class="flex items-center space-x-3">
              <div class="w-10 h-10 bg-gradient-to-br from-green-500 to-blue-600 rounded-xl flex items-center justify-center shadow-lg">
              </div>
              <div>
                <h1 class="text-xl font-bold text-gray-900">Chat do Pedido</h1>
                <div class="flex items-center mt-1">
                  <div class={get_connection_indicator_class(@connected)} aria-hidden="true"></div>
                  <span class="text-sm text-gray-600 font-medium">{@connection_status}</span>
                </div>
              </div>
            </div>
          </div>

          <div class="flex items-center space-x-2">
            <button
              class="p-2.5 text-gray-500 hover:text-gray-700 transition-all duration-200 rounded-lg hover:bg-gray-100 hover:shadow-sm"
              aria-label="Exportar conversa"
              title="Exportar conversa"
            >
            </button>
            <button
              class="p-2.5 text-gray-500 hover:text-gray-700 transition-all duration-200 rounded-lg hover:bg-gray-100 hover:shadow-sm"
              aria-label="Mais opções"
              title="Mais opções"
            >
            </button>
          </div>
        </header>

    <!-- Error Message -->
        <%= if @message_error do %>
          <div class="mx-6 mt-4 p-4 bg-red-50 border border-red-200 rounded-lg flex items-center justify-between animate-pulse">
            <div class="flex items-center">
              <span class="text-sm text-red-700">{@message_error}</span>
            </div>
            <button phx-click="clear_error" class="text-red-500 hover:text-red-700 transition-colors">
            </button>
          </div>
        <% end %>

    <!-- Messages Container -->
        <div
          id="messages"
          class="flex-1 overflow-y-auto p-6 space-y-4 bg-gradient-to-b from-gray-50/30 to-white scroll-smooth min-h-0"
          role="log"
          aria-live="polite"
          aria-label="Mensagens do chat"
        >

    <!-- Load More Button -->
          <%= if @has_more_messages do %>
            <div class="flex justify-center pb-4">
              <button
                phx-click="load_older_messages"
                disabled={@loading_messages}
                class="px-4 py-2 text-sm text-gray-600 bg-white border border-gray-200 rounded-lg hover:bg-gray-50 transition-all duration-200 disabled:opacity-50 disabled:cursor-not-allowed flex items-center space-x-2 shadow-sm hover:shadow-md"
              >
                <%= if @loading_messages do %>
                  <span>Carregando...</span>
                <% else %>
                  <span>Carregar mensagens anteriores</span>
                <% end %>
              </button>
            </div>
          <% end %>

          <%= if Enum.empty?(@messages) do %>
            <div class="flex flex-col items-center justify-center h-full text-center py-12">
              <div class="w-20 h-20 bg-gradient-to-br from-blue-100 to-indigo-100 rounded-full flex items-center justify-center mb-6 shadow-sm">
              </div>
              <h2 class="text-xl font-semibold text-gray-900 mb-3">Nenhuma mensagem ainda</h2>
              <p class="text-gray-600 max-w-md">
                Seja o primeiro a enviar uma mensagem neste chat do pedido!
              </p>
            </div>
          <% else %>
            <%= for msg <- @messages do %>
              <div
                class={"flex mb-2 " <> if(msg.sender_id == @current_user, do: "justify-end", else: "justify-start")}
                role="article"
                aria-label={"Mensagem de " <> msg.sender_id}
              >
                <div class={
                  "relative max-w-xs md:max-w-md px-4 py-2 rounded-2xl shadow transition-all duration-200 " <>
                  if(msg.sender_id == @current_user,
                    do: "bg-gradient-to-br from-green-400 to-green-500 text-white rounded-br-sm",
                    else: "bg-gray-100 text-gray-900 rounded-bl-sm")
                }>
                  <%= if msg.sender_id != @current_user do %>
                    <div class="text-xs font-semibold text-gray-600 mb-1">{msg.sender_id}</div>
                  <% end %>
                  <div class="text-sm break-words">{msg.text}</div>
                  <%= if msg.image_url do %>
                    <img
                      src={msg.image_url}
                      class="w-32 h-32 object-cover rounded-lg cursor-pointer hover:scale-105 transition mt-2"
                      phx-click="show_image"
                      phx-value-url={msg.image_url}
                      alt="Imagem enviada"
                    />
                  <% end %>
                  <div class="flex items-center justify-end mt-1 space-x-1">
                    <span class="text-xs text-gray-300">{format_time(msg.inserted_at)}</span>
                    <%= if msg.sender_id == @current_user do %>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

    <!-- Message Input -->
        <footer class="p-6 border-t border-gray-200 bg-white/95 backdrop-blur-sm flex-shrink-0 shadow-lg">
          <form
            phx-submit="send_message"
            phx-drop-target={@uploads.image.ref}
            class="flex items-end space-x-4"
            role="form"
            aria-label="Enviar mensagem"
          >
            <div class="flex-1 relative">
              <label for="message-input" class="sr-only">Digite sua mensagem</label>
              <!-- Preview da imagem -->
              <%= if @uploads[:image] && @uploads.image.entries != [] do %>
                <div class="mb-2 flex items-center space-x-2">
                  <%= for entry <- @uploads.image.entries do %>
                    <div class="relative inline-block mr-2 mb-2">
                      <!-- Preview da imagem -->
                      <.live_img_preview
                        entry={entry}
                        class="w-20 h-20 object-cover rounded-lg border border-gray-200 shadow"
                      />

    <!-- Barra de progresso animada -->
                      <div class="absolute bottom-0 left-0 w-full h-2 bg-gray-200 rounded-b-lg overflow-hidden">
                        <div
                          class="h-full bg-blue-500 transition-all duration-300"
                          style={"width: #{entry.progress}%"}
                        >
                        </div>
                      </div>

    <!-- Ícone de carregando enquanto não terminou -->
                      <%= if entry.progress < 100 do %>
                        <div class="absolute inset-0 flex items-center justify-center bg-white/60 rounded-lg">
                        </div>
                      <% end %>

    <!-- Botão para remover o upload -->
                      <button
                        type="button"
                        phx-click="cancel_upload"
                        phx-value-ref={entry.ref}
                        class="absolute top-0 right-0 bg-white/80 rounded-full p-1 text-red-500 hover:text-red-700"
                        title="Remover imagem"
                      >
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
              <input
                id="message-input"
                name="message"
                value={@message}
                placeholder="Digite sua mensagem..."
                class="w-full px-4 py-3.5 pr-12 border border-gray-300 rounded-2xl focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 bg-white shadow-sm hover:border-gray-400 hover:shadow-md"
                autocomplete="off"
                maxlength={ChatConfig.security_config()[:max_message_length]}
                required
                disabled={not @connected}
              />
              <label
                for="image-upload"
                class="absolute right-3 top-1/2 transform -translate-y-1/2 p-1.5 text-gray-400 hover:text-gray-600 transition-all duration-200 rounded-lg hover:bg-gray-100 cursor-pointer"
                aria-label="Anexar arquivo"
                title="Anexar arquivo"
              >
                <input
                  id="image-upload"
                  type="file"
                  name="image"
                  accept="image/*"
                  class="hidden"
                  phx-drop-target={@uploads.image.ref}
                  multiple={false}
                />
              </label>
            </div>

            <button
              type="submit"
              disabled={
                not @connected or (String.trim(@message) == "" and @uploads.image.entries == [])
              }
              class="px-6 py-3.5 bg-gradient-to-r from-blue-500 to-blue-600 text-white rounded-2xl hover:from-blue-600 hover:to-blue-700 focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-all duration-200 font-semibold flex items-center space-x-2 shadow-md hover:shadow-lg disabled:opacity-50 disabled:cursor-not-allowed transform hover:scale-105"
              aria-label="Enviar mensagem"
            >
              <span>Enviar</span>
            </button>
          </form>
        </footer>
      </main>
    </div>

    <%= if @modal_image_url do %>
      <div
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/70"
        phx-click="close_image_modal"
      >
        <div class="relative" phx-click="stopPropagation">
          <img
            src={@modal_image_url}
            class="max-h-[80vh] max-w-[90vw] rounded-lg shadow-2xl border-4 border-white"
            alt="Imagem ampliada"
          />
          <button
            class="absolute top-2 right-2 bg-white/80 rounded-full p-2 text-gray-700 hover:text-red-600"
            phx-click="close_image_modal"
          >
          </button>
        </div>
      </div>
    <% end %>
    """
  end

  # Funções auxiliares privadas
  defp process_image_upload(socket) do
    consume_uploaded_entries(socket, :image, fn %{path: path, client_name: name}, _entry ->
      filename = "#{UUID.uuid4()}_#{name}"

      case App.Minio.upload_file(path, filename) do
        {:ok, url} -> url
        _ -> nil
      end
    end)
    |> List.first()
  end

  defp send_chat_message(socket, text, image_url) do
    case App.Chat.send_message(
           socket.assigns.order_id,
           socket.assigns.current_user,
           text,
           image_url
         ) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> assign(:message, "")
         |> assign(:message_error, nil)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :message_error, "Erro ao enviar mensagem")}
    end
  end

  defp initialize_chat_socket(socket, order_id) do
    topic = "order:#{order_id}"

    setup_presence_if_connected(socket, topic, order_id)
    order = load_order_data(order_id)
    {messages, has_more} = load_messages(order_id)

    setup_socket_assigns(socket, order_id, topic, order, messages, has_more)
  end

  defp setup_presence_if_connected(socket, topic, _order_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, topic)

      user_data = %{
        user_id: socket.assigns[:user_id] || "anonymous",
        name: socket.assigns[:name] || ChatConfig.default_username(),
        joined_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        user_agent: get_connect_info(socket, :user_agent) || "Unknown"
      }

      Presence.track(self(), topic, socket.id, user_data)
    end
  end

  defp load_order_data(order_id) do
    case App.Orders.get_order(order_id) do
      nil ->
        %{
          "orderId" => order_id,
          "status" => "Não encontrado",
          "customerName" => "N/A",
          "amount" => "0",
          "deliveryType" => "N/A",
          "deliveryDate" => ""
        }
      order -> order
    end
  end

  defp load_messages(order_id) do
    case App.Chat.list_messages_for_order(order_id, ChatConfig.default_message_limit()) do
      {:ok, msgs, more} -> {msgs, more}
    end
  end

  defp setup_socket_assigns(socket, order_id, topic, order, messages, has_more) do
    presences = Presence.list(topic)
    users_online = extract_users_from_presences(presences)

    socket
    |> assign(:order_id, order_id)
    |> assign(:order, order)
    |> assign(:messages, messages)
    |> assign(:has_more_messages, has_more)
    |> assign(:presences, presences)
    |> assign(:message, "")
    |> assign(:users_online, users_online)
    |> assign(:current_user, socket.assigns[:name] || ChatConfig.default_username())
    |> assign(:connected, connected?(socket))
    |> assign(:connection_status, if(connected?(socket), do: "Conectado", else: "Desconectado"))
    |> assign(:topic, topic)
    |> assign(:loading_messages, false)
    |> assign(:message_error, nil)
    |> assign(:modal_image_url, nil)
    |> allow_upload(:image,
      accept: ~w(.jpg .jpeg .png .gif),
      max_entries: 1,
      max_file_size: 5_000_000
    )
  end

  defp extract_users_from_presences(presences) do
    presences
    |> Map.values()
    |> Enum.flat_map(fn %{metas: metas} ->
      Enum.map(metas, fn %{name: name} -> name end)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp load_older_messages_async(socket) do
    order_id = socket.assigns.order_id
    current_count = length(socket.assigns.messages)

    Task.start(fn ->
      case App.Chat.list_messages_for_order(
             order_id,
             ChatConfig.pagination_config()[:default_limit],
             current_count
           ) do
        {:ok, older_messages, has_more} ->
          send(self(), {:older_messages_loaded, older_messages, has_more})
      end
    end)

    socket
  end

  defp get_user_initial(user) when is_binary(user) and user != "" do
    user |> String.first() |> String.upcase()
  end

  defp get_user_initial(_), do: "U"

  defp get_status_class(status) do
    base_classes = "px-3 py-1.5 text-xs font-semibold rounded-full border shadow-sm"

    case String.downcase(status || "") do
      "ativo" -> "#{base_classes} bg-green-100 text-green-800 border-green-200"
      "pendente" -> "#{base_classes} bg-yellow-100 text-yellow-800 border-yellow-200"
      "cancelado" -> "#{base_classes} bg-red-100 text-red-800 border-red-200"
      "concluído" -> "#{base_classes} bg-blue-100 text-blue-800 border-blue-200"
      _ -> "#{base_classes} bg-gray-100 text-gray-800 border-gray-200"
    end
  end

  defp get_connection_indicator_class(connected) do
    base_classes = "w-1.5 h-1.5 rounded-full mr-1.5"

    if connected,
      do: "#{base_classes} bg-green-500 animate-pulse",
      else: "#{base_classes} bg-red-500"
  end

  defp get_connection_text_class(connected) do
    if connected, do: "text-green-600", else: "text-red-600"
  end

  defp format_currency(amount) when is_binary(amount) do
    case Float.parse(amount) do
      {float_amount, _} -> :erlang.float_to_binary(float_amount, decimals: 2)
      :error -> amount
    end
  end

  defp format_currency(amount) when is_number(amount) do
    :erlang.float_to_binary(amount * 1.0, decimals: 2)
  end

  defp format_currency(_), do: "0.00"

  defp format_date(date_string) when is_binary(date_string) and date_string != "" do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} ->
        "#{String.pad_leading("#{datetime.day}", 2, "0")}/#{String.pad_leading("#{datetime.month}", 2, "0")}/#{datetime.year}"

      _ ->
        date_string
    end
  end

  defp format_date(_), do: "Data não disponível"

  defp format_time(datetime) do
    case datetime do
      %DateTime{} ->
        "#{String.pad_leading("#{datetime.hour}", 2, "0")}:#{String.pad_leading("#{datetime.minute}", 2, "0")}"

      _ ->
        "Hora não disponível"
    end
  end
end
