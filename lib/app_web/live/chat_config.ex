defmodule AppWeb.ChatConfig do
  @moduledoc """
  Configurações centralizadas para o sistema de chat.

  Este módulo centraliza todos os números mágicos, strings e configurações
  utilizadas no ChatLive e componentes relacionados, facilitando manutenção
  e consistência em toda a aplicação.
  """

  @doc """
  Configurações de UI e layout do chat.
  """
  def ui_config do
    %{
      sidebar_width: "w-56",
      max_message_width: "max-w-[90%] sm:max-w-[85%] md:max-w-md lg:max-w-lg xl:max-w-xl",
      primary_color: "blue",
      success_color: "green",
      warning_color: "amber",
      error_color: "red",
      transition_duration: "duration-200",
      hover_transition: "transition-all duration-200",
      modal_z_index: "z-50",
      sidebar_z_index: "z-30",
      overlay_z_index: "z-20",
      dropdown_z_index: "z-10"
    }
  end

  @doc """
  Configurações relacionadas ao envio e exibição de mensagens.
  """
  def message_config do
    %{
      max_message_length: 2000,
      min_message_length: 1,
      default_message_limit: 50,
      load_more_limit: 25,
      typing_indicator_delay: 1000,
      connection_check_interval: 5000,
      max_mentions_per_message: 10,
      max_attachments_per_message: 3
    }
  end

  @doc """
  Configurações para upload de arquivos e imagens.
  """
  def upload_config do
    %{
      allowed_image_types: ~w(.jpg .jpeg .png .gif),
      max_file_size: 5_000_000,
      max_entries: 3,
      preview_size: "w-20 h-20 sm:w-32 sm:h-32",
      auto_upload: true,
      temp_dir_prefix: "juruconnect_uploads"
    }
  end

  @doc """
  Configurações de segurança e validação.
  """
  def security_config do
    %{
      max_message_length: 2000,
      max_username_length: 50,
      max_messages_per_minute: 30,
      max_uploads_per_hour: 20,
      sanitize_html: true,
      prevent_xss: true,
      session_timeout: 30 * 60 * 1000,
      idle_timeout: 5 * 60 * 1000
    }
  end

  @doc """
  Configurações de paginação para diferentes listas.
  """
  def pagination_config do
    %{
      default_limit: 50,
      max_limit: 100,
      comments_limit: 20,
      activities_limit: 20,
      tags_search_limit: 10,
      online_users_limit: 50
    }
  end

  @doc """
  Configurações para sistema de notificações.
  """
  def notification_config do
    %{
      toast_duration: %{
        success: 3000,
        error: 5000,
        warning: 4000,
        info: 3000
      },
      enable_sound: true,
      sound_volume: 0.7,
      enable_desktop_notifications: true,
      notification_icon: "/images/notification-icon.svg"
    }
  end

  @doc """
  Configurações para atalhos de teclado.
  """
  def keyboard_shortcuts do
    %{
      focus_input: "1",
      toggle_sidebar: "2",
      manage_tags: "3",
      exit_chat: "4",
      open_search: "Ctrl+K",
      clear_search: "Escape",
      send_message: "Ctrl+Enter",
      stop_typing: "Backspace",
      close_modals: "Escape",
      show_shortcuts: "Ctrl+/"
    }
  end

  @doc """
  Configurações para diferentes status e estados.
  """
  def status_config do
    %{
      treaty_statuses: %{
        "active" => %{label: "Ativo", color: "emerald", icon: "check-circle"},
        "inactive" => %{label: "Inativo", color: "amber", icon: "clock"},
        "cancelled" => %{label: "Cancelado", color: "red", icon: "x-circle"},
        "completed" => %{label: "Concluído", color: "blue", icon: "check"},
        "closed" => %{label: "Encerrado", color: "gray", icon: "lock-closed"}
      },
      connection_statuses: %{
        "connected" => %{label: "Conectado", color: "emerald", icon: "wifi"},
        "disconnected" => %{label: "Desconectado", color: "red", icon: "wifi-off"},
        "reconnecting" => %{label: "Reconectando", color: "amber", icon: "refresh"}
      },
      message_statuses: %{
        "sent" => %{label: "Enviado", color: "gray", icon: "check"},
        "delivered" => %{label: "Entregue", color: "gray", icon: "check-double"},
        "read" => %{label: "Lido", color: "blue", icon: "check-double"}
      }
    }
  end

  @doc """
  Configurações para sistema de avaliação de tratativas.
  """
  def rating_config do
    %{
      rating_options: ["péssimo", "ruim", "bom", "excelente"],
      rating_colors: %{
        "péssimo" => "red",
        "ruim" => "orange",
        "bom" => "blue",
        "excelente" => "green"
      },
      close_reasons: [
        "resolved",
        "cancelled",
        "duplicate",
        "invalid",
        "other"
      ]
    }
  end

  @doc """
  Configurações para sistema de comentários internos.
  """
  def comments_config do
    %{
      comment_types: %{
        "internal_note" => %{label: "Interno", color: "blue", icon: "lock-closed"},
        "public_note" => %{label: "Público", color: "green", icon: "globe"}
      },
      max_comment_length: 1000,
      max_comments_per_treaty: 100,
      max_display_height: "max-h-48",
      auto_expand_threshold: 5
    }
  end

  @doc """
  Configurações para sistema de busca de mensagens.
  """
  def search_config do
    %{
      debounce_delay: 300,
      min_search_length: 2,
      content_types: ["all", "text", "images"],
      max_search_results: 100,
      search_history_limit: 10,
      highlight_class: "bg-yellow-200 text-yellow-800",
      max_highlight_length: 50
    }
  end

  @doc """
  Configurações para sistema de presença de usuários.
  """
  def presence_config do
    %{
      heartbeat_interval: 30_000,
      offline_threshold: 60_000,
      max_displayed_users: 20,
      show_user_agent: false,
      track_join_time: true,
      track_user_agent: true
    }
  end

  @doc """
  Configurações para sistema de tags.
  """
  def tags_config do
    %{
      max_tags_per_treaty: 10,
      max_tag_name_length: 50,
      max_tag_description_length: 200,
      min_search_length: 2,
      search_results_limit: 20,
      default_colors: [
        "#3B82F6", "#EF4444", "#10B981", "#F59E0B",
        "#8B5CF6", "#EC4899", "#06B6D4", "#84CC16"
      ]
    }
  end

  @doc """
  Configurações para sistema de atividades e histórico.
  """
  def activities_config do
    %{
      default_limit: 20,
      max_limit: 100,
      cache_duration: 5 * 60 * 1000,
      activity_types: [
        "message_sent",
        "treaty_created",
        "treaty_closed",
        "treaty_reopened",
        "tag_added",
        "tag_removed",
        "comment_added"
      ]
    }
  end

  @doc """
  Configurações para otimização de performance.
  """
  def performance_config do
    %{
      typing_debounce: 1000,
      search_debounce: 300,
      message_cache_size: 1000,
      presence_cache_duration: 30_000,
      lazy_load_threshold: 20,
      preload_messages: 10,
      batch_size: 50,
      max_concurrent_uploads: 3
    }
  end

  @doc """
  Configurações para acessibilidade e usabilidade.
  """
  def accessibility_config do
    %{
      aria_labels: %{
        message_input: "Campo de entrada de mensagem",
        send_button: "Enviar mensagem",
        sidebar_toggle: "Abrir sidebar com tags e usuários online",
        search_button: "Buscar mensagens",
        close_button: "Fechar"
      },
      focus_management: %{
        trap_focus_in_modals: true,
        restore_focus_on_close: true,
        focus_visible_class: "focus:ring-2 focus:ring-blue-500"
      },
      contrast_ratios: %{
        normal_text: 4.5,
        large_text: 3.0,
        ui_components: 3.0
      }
    }
  end

  @doc """
  Configurações específicas para ambiente de desenvolvimento.
  """
  def development_config do
    %{
      enable_debug_logs: true,
      show_performance_metrics: false,
      enable_hot_reload: true,
      show_detailed_errors: true,
      log_all_events: false
    }
  end

  @doc """
  Configurações específicas para ambiente de produção.
  """
  def production_config do
    %{
      enable_compression: true,
      minify_assets: true,
      enable_csp: true,
      enable_hsts: true,
      enable_metrics: true,
      log_level: :info
    }
  end

  @doc """
  Retorna configuração baseada no ambiente atual.
  """
  def get_env_config do
    case Application.get_env(:app, :env) do
      :dev -> development_config()
      :prod -> production_config()
      _ -> development_config()
    end
  end

  @doc """
  Retorna configuração específica por categoria.
  """
  def get_config(category) when is_atom(category) do
    config_functions = get_config_functions()
    case Map.get(config_functions, category) do
      nil -> %{}
      config_function -> apply(__MODULE__, config_function, [])
    end
  end

  defp get_config_functions do
    %{
      ui: :ui_config,
      messages: :message_config,
      upload: :upload_config,
      security: :security_config,
      pagination: :pagination_config,
      notifications: :notification_config,
      keyboard: :keyboard_shortcuts,
      status: :status_config,
      rating: :rating_config,
      comments: :comments_config,
      search: :search_config,
      presence: :presence_config,
      tags: :tags_config,
      activities: :activities_config,
      performance: :performance_config,
      accessibility: :accessibility_config,
      development: :development_config,
      production: :production_config
    }
  end

  @doc """
  Retorna valor específico de uma configuração.
  """
  def get_config_value(category, key) do
    category
    |> get_config()
    |> Map.get(key)
  end

  @doc """
  Retorna configuração mesclada com valores padrão.
  """
  def get_config_with_defaults(category, defaults \\ %{}) do
    category
    |> get_config()
    |> Map.merge(defaults)
  end

  @doc """
  Configurações legacy para manter compatibilidade com código existente.
  """
  def default_username, do: "Usuario"
  def default_message_limit, do: message_config().default_message_limit
  def max_message_length, do: security_config().max_message_length
end
