defmodule App.ChatConfig do
  @moduledoc """
  Configurações centralizadas para o sistema de chat.

  Este módulo contém todas as configurações relacionadas ao chat,
  incluindo limites de mensagens, timeouts, circuit breakers e valores padrão.
  """

  @doc """
  Retorna o limite padrão de mensagens carregadas ao entrar em uma sala.
  """
  def default_message_limit, do: 50

  @doc """
  Retorna o limite máximo de mensagens que podem ser carregadas de uma vez.
  """
  def max_message_limit, do: 100

  @doc """
  Retorna o nome de usuário padrão quando não é possível determinar o nome real.
  """
  def default_username, do: "Usuário"

  @doc """
  Retorna o timeout de inatividade para salas de chat (em minutos).
  Após este período, a sala será automaticamente encerrada.
  """
  def room_inactivity_timeout, do: 30

  @doc """
  Retorna a configuração do circuit breaker para o serviço de preview de links.
  """
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

  @doc """
  Retorna a configuração de paginação para carregamento de mensagens antigas.
  """
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

  @doc """
  Retorna configurações de performance para o chat.
  """
  def performance_config do
    %{
      # Tamanho do cache de mensagens em memória
      message_cache_size: 1000,
      # Intervalo de atualização de presença (ms)
      presence_update_interval: 30_000,
      # Timeout para indicador de digitação (ms)
      typing_timeout: 5000
    }
  end

  @doc """
  Retorna configurações de segurança para o chat.
  """
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

  @doc """
  Retorna configurações de notificação para o chat.
  """
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

  @doc """
  Retorna configurações de UI/UX para o chat.
  """
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

  @doc """
  Retorna configurações de desenvolvimento/debug.
  """
  def debug_config do
    %{
      # Habilitar logs de debug
      enable_debug_logs: false,
      # Logar eventos de mensagens
      log_message_events: false,
      # Logar eventos de presença
      log_presence_events: false,
      # Logar métricas de performance
      log_performance_metrics: false
    }
  end

  @doc """
  Retorna todas as configurações como um mapa.
  """
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
