defmodule App.ChatConfig do
  @moduledoc """
  Configurações centralizadas para o sistema de chat.

  Este módulo contém todas as configurações relacionadas ao chat,
  incluindo limites de mensagens, timeouts, circuit breakers e valores padrão.
  """

  def default_message_limit, do: 50

  def max_message_limit, do: 100

  def default_username, do: "Usuário"

  def max_message_length, do: 1000

  def room_inactivity_timeout, do: 30

  def link_preview_circuit_breaker do
    %{
      # Número máximo de falhas antes de abrir o circuito
      max_failures: 5,
      # Período de tempo para contar falhas (segundos)
      failure_period_s: 60,
      # Tempo para tentar fechar o circuito novamente (segundos)
      reset_period_s: 300
    }
  end

  def pagination_config do
    %{
      # Número padrão de mensagens por página
      default_limit: 20,
      # Limite máximo de mensagens por página
      max_limit: 50,
      # Offset máximo para evitar consultas muito antigas
      max_offset: 1000
    }
  end

  def performance_config do
    %{
      # Tamanho do cache de mensagens em memória
      message_cache_size: 1000,
      presence_update_interval: 1_000,
      # Timeout para indicador de digitação (ms)
      typing_timeout: 3000
    }
  end

  def typing_timeout, do: performance_config()[:typing_timeout]

  def security_config do
    %{
      # Comprimento máximo de uma mensagem
      max_message_length: 1000,
      # Máximo de mensagens por minuto por usuário
      rate_limit_messages: 10,
      # Janela de tempo para rate limiting (segundos)
      rate_limit_window: 60
    }
  end

  def notification_config do
    %{
      # Habilitar som para novas mensagens
      enable_sound: true,
      # Habilitar notificações desktop
      enable_desktop_notifications: true,
      # Tempo de exibição da notificação (ms)
      notification_timeout: 5000
    }
  end

  def ui_config do
    %{
      # Habilitar scroll automático para novas mensagens
      auto_scroll_enabled: true,
      # Mostrar timestamps nas mensagens
      show_timestamps: true,
      # Mostrar avatares dos usuários
      show_user_avatars: true,
      # Agrupar mensagens do mesmo usuário (5 min)
      message_grouping_timeout: 300_000
    }
  end

  def debug_config do
    %{
      enable_debug_logs: true,
      log_message_events: false,
      log_presence_events: true,
      log_performance_metrics: true
    }
  end

  def all_configs do
    %{
      default_message_limit: default_message_limit(),
      max_message_limit: max_message_limit(),
      default_username: default_username(),
      room_inactivity_timeout: room_inactivity_timeout(),
      link_preview_circuit_breaker: link_preview_circuit_breaker(),
      pagination: pagination_config(),
      performance: performance_config(),
      security: security_config(),
      notification: notification_config(),
      ui: ui_config(),
      debug: debug_config()
    }
  end
end
