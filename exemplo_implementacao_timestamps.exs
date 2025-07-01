# Exemplo prático de implementação de melhorias no frontend do chat

defmodule AppWeb.ChatHelpers do
  @moduledoc """
  Helpers para melhorar a experiência do usuário no chat
  """

  use Phoenix.HTML

  @doc """
  Formata timestamp de forma relativa ("2 min atrás", "ontem", etc.)
  """
  def format_time_relative(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 ->
        "agora mesmo"

      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes} min atrás"

      diff_seconds < 86400 ->
        hours = div(diff_seconds, 3600)
        "#{hours}h atrás"

      diff_seconds < 604800 ->
        days = div(diff_seconds, 86400)
        if days == 1, do: "ontem", else: "#{days} dias atrás"

      true ->
        format_time_absolute(datetime)
    end
  end

  @doc """
  Formata timestamp absoluto para datas antigas
  """
  def format_time_absolute(datetime) do
    case datetime do
      %DateTime{} ->
        day = String.pad_leading("#{datetime.day}", 2, "0")
        month = String.pad_leading("#{datetime.month}", 2, "0")
        "#{day}/#{month}/#{datetime.year}"
      _ ->
        "Data indisponível"
    end
  end

  @doc """
  Agrupa mensagens consecutivas do mesmo usuário
  """
  def group_consecutive_messages(messages) do
    messages
    |> Enum.chunk_by(&{&1.sender_id, &1.tipo})
    |> Enum.map(fn group ->
      case group do
        [single_message] ->
          Map.put(single_message, :is_grouped, false)

        multiple_messages ->
          multiple_messages
          |> Enum.with_index()
          |> Enum.map(fn {msg, index} ->
            cond do
              index == 0 -> Map.put(msg, :is_grouped, :first)
              index == length(multiple_messages) - 1 -> Map.put(msg, :is_grouped, :last)
              true -> Map.put(msg, :is_grouped, :middle)
            end
          end)
      end
    end)
    |> List.flatten()
  end

  @doc """
  Detecta e highlighta menções no texto
  """
  def highlight_mentions(text) do
    Regex.replace(~r/@(\w+)/, text, fn _match, username ->
      ~s(<span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-full bg-blue-100 text-blue-800 border border-blue-200">@#{username}</span>)
    end)
    |> Phoenix.HTML.raw()
  end

  @doc """
  Detecta e cria previews de links
  """
  def create_link_previews(text) do
    link_regex = ~r/(https?:\/\/)?([\da-z\.-]+)\.([a-z\.]{2,6})([\/\w \.-]*)*\/?/i

    Regex.replace(link_regex, text, fn url ->
      sanitized_url = if String.starts_with?(url, "http"), do: url, else: "https://#{url}"

      ~s(<a href="#{sanitized_url}" target="_blank" rel="noopener noreferrer"
          class="inline-flex items-center space-x-1 text-blue-600 hover:text-blue-800 transition-colors">
          <span>#{url}</span>
          <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
            <path d="M11 3a1 1 0 100 2h2.586l-6.293 6.293a1 1 0 101.414 1.414L15 6.414V9a1 1 0 102 0V4a1 1 0 00-1-1h-5z"/>
            <path d="M5 5a2 2 0 00-2 2v8a2 2 0 002 2h8a2 2 0 002-2v-3a1 1 0 10-2 0v3H5V7h3a1 1 0 000-2H5z"/>
          </svg>
        </a>)
    end)
    |> Phoenix.HTML.raw()
  end
end

# Template melhorado com as novas funcionalidades
"""
<!-- Mensagens com agrupamento e timestamps relativos -->
<%= for msg <- group_consecutive_messages(@filtered_messages) do %>
  <%= if is_system_message?(msg) do %>
    <!-- Sistema messages unchanged -->
  <% else %>
    <div class={get_message_container_class(msg)} data-message-id={msg.id}>
      <!-- Avatar só na primeira mensagem do grupo -->
      <%= if msg.is_grouped in [false, :first] do %>
        <div class={get_avatar_class(msg)}>
          <span class="text-white font-bold text-sm">
            {get_user_initial(msg.sender_name)}
          </span>
        </div>
      <% else %>
        <div class="w-8"></div> <!-- Espaçamento para alinhamento -->
      <% end %>

      <div class="flex-1 min-w-0">
        <!-- Nome do usuário só na primeira mensagem do grupo -->
        <%= if msg.is_grouped in [false, :first] and msg.sender_id != @current_user_id do %>
          <div class={get_username_class(msg)}>
            {msg.sender_name}
            <span class="text-xs text-gray-400 font-normal ml-2">
              {format_time_relative(msg.inserted_at)}
            </span>
          </div>
        <% end %>

        <!-- Conteúdo da mensagem -->
        <div class={get_message_bubble_class(msg)}>
          <%= if is_reply_message?(msg) do %>
            <!-- Reply preview -->
          <% end %>

          <!-- Texto com links e menções -->
          <div class="text-base break-words leading-relaxed">
            <%= if has_mentions?(msg) do %>
              {highlight_mentions(msg.text)}
            <% else %>
              {create_link_previews(msg.text)}
            <% end %>
          </div>

          <!-- Timestamp e status na última mensagem do grupo -->
          <%= if msg.is_grouped in [false, :last] do %>
            <div class="flex items-center justify-between mt-2 text-xs">
              <div class="flex items-center space-x-2">
                <!-- Botões de ação -->
              </div>

              <div class="flex items-center space-x-1">
                <span class="text-gray-400" title={format_time_absolute(msg.inserted_at)}>
                  {format_time_relative(msg.inserted_at)}
                </span>
                <%= if msg.sender_id == @current_user_id do %>
                  <span class={get_status_indicator_class(msg)}>
                    {get_status_text(msg)}
                  </span>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
  <% end %>
<% end %>
"""

# JavaScript Hook melhorado
"""
// ChatHook com Intersection Observer e funcionalidades avançadas
Hooks.EnhancedChatHook = {
  mounted() {
    this.setupIntersectionObserver();
    this.setupKeyboardShortcuts();
    this.setupAutoScroll();
    this.isLoading = false;
  },

  setupIntersectionObserver() {
    const loadTrigger = document.querySelector('[phx-click="load_older_messages"]');

    if (loadTrigger) {
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting && !this.isLoading) {
            this.isLoading = true;
            this.pushEvent("load_older_messages", {});

            // Reset loading state após 2 segundos para evitar spam
            setTimeout(() => { this.isLoading = false; }, 2000);
          }
        });
      }, {
        threshold: 0.5,
        rootMargin: '100px 0px' // Carrega 100px antes de chegar no elemento
      });

      observer.observe(loadTrigger);
      this.intersectionObserver = observer;
    }
  },

  setupKeyboardShortcuts() {
    document.addEventListener('keydown', (e) => {
      // Ctrl/Cmd + K para busca
      if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        const searchButton = document.querySelector('[phx-click="toggle_search"]');
        if (searchButton) searchButton.click();
      }

      // Esc para fechar modais
      if (e.key === 'Escape') {
        const closeButtons = document.querySelectorAll('[phx-click="close_thread"], [phx-click="cancel_reply"]');
        closeButtons.forEach(btn => btn.click());
      }

      // Enter para enviar (quando input está focado)
      if (e.key === 'Enter' && !e.shiftKey && e.target.id === 'message-input') {
        e.preventDefault();
        const form = e.target.closest('form');
        if (form) form.requestSubmit();
      }
    });
  },

  setupAutoScroll() {
    // Scroll automático apenas se usuário estiver próximo do final
    this.handleEvent("new_message", () => {
      const container = document.getElementById('messages');
      if (container) {
        const isNearBottom = container.scrollTop + container.clientHeight >= container.scrollHeight - 100;

        if (isNearBottom) {
          this.scrollToBottom();
        } else {
          this.showNewMessageIndicator();
        }
      }
    });
  },

  scrollToBottom() {
    const container = document.getElementById('messages');
    if (container) {
      container.scrollTo({
        top: container.scrollHeight,
        behavior: 'smooth'
      });
    }
  },

  showNewMessageIndicator() {
    // Mostra indicador de nova mensagem quando usuário não está no final
    const indicator = document.createElement('div');
    indicator.className = `
      fixed bottom-20 right-4 z-10 bg-blue-500 text-white
      px-4 py-2 rounded-full shadow-lg cursor-pointer
      animate-bounce transition-all duration-300
    `;
    indicator.innerHTML = '↓ Nova mensagem';
    indicator.onclick = () => {
      this.scrollToBottom();
      indicator.remove();
    };

    document.body.appendChild(indicator);

    // Remove automaticamente após 5 segundos
    setTimeout(() => {
      if (indicator.parentNode) indicator.remove();
    }, 5000);
  },

  destroyed() {
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect();
    }
  }
}
"""

# CSS melhorado
"""
/* Estilos para mensagens agrupadas */
.message-group-first {
  @apply rounded-t-2xl rounded-b-lg;
}

.message-group-middle {
  @apply rounded-lg my-1;
}

.message-group-last {
  @apply rounded-t-lg rounded-b-2xl;
}

.message-single {
  @apply rounded-2xl;
}

/* Animações suaves */
.message-appear {
  animation: messageAppear 0.3s ease-out;
}

@keyframes messageAppear {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* Indicadores de status melhorados */
.status-sent {
  @apply text-gray-400;
}

.status-delivered {
  @apply text-blue-400;
}

.status-read {
  @apply text-green-400;
}

/* Loading skeleton */
.message-skeleton {
  @apply animate-pulse;
}

.message-skeleton .skeleton-line {
  @apply h-4 bg-gray-200 rounded mb-2;
}

.message-skeleton .skeleton-line:last-child {
  @apply w-3/4;
}

/* Responsividade aprimorada */
@media (max-width: 640px) {
  .message-bubble {
    @apply max-w-[85%] text-sm;
  }

  .message-actions {
    @apply hidden group-hover:flex;
  }
}

/* Dark mode support */
@media (prefers-color-scheme: dark) {
  .message-bubble {
    @apply bg-gray-800 text-white border-gray-700;
  }

  .message-bubble.own {
    @apply bg-blue-600;
  }

  .skeleton-line {
    @apply bg-gray-700;
  }
}
"""

# Função auxiliar para classes CSS
"""
defp get_message_container_class(msg) do
  base = "flex items-start space-x-3 px-4 py-1 group hover:bg-gray-50/30 transition-colors"

  case msg.is_grouped do
    false -> base <> " message-single"
    :first -> base <> " message-group-first"
    :middle -> base <> " message-group-middle"
    :last -> base <> " message-group-last"
  end
end

defp get_message_bubble_class(msg) do
  base_classes = "relative px-4 py-3 transition-all duration-200 message-appear"

  spacing_classes = case msg.is_grouped do
    false -> "mb-4"
    :first -> "mb-1"
    :middle -> "my-1"
    :last -> "mt-1 mb-4"
  end

  color_classes = if msg.sender_id == @current_user_id do
    "bg-[#DCF8C6] text-gray-800 rounded-br-sm"
  else
    "bg-white border border-gray-200 text-gray-900 rounded-bl-sm shadow-sm"
  end

  \"\#{base_classes} \#{spacing_classes} \#{color_classes}\"
end
"""
