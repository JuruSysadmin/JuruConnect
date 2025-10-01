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
  Retorna o comprimento máximo permitido para uma mensagem.
  """
  def max_message_length, do: security_config().max_message_length

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
      max_failures: 5,           # Número máximo de falhas antes de abrir o circuito
      failure_period_s: 60,      # Período de tempo para contar falhas (segundos)
      reset_period_s: 300        # Tempo para tentar fechar o circuito novamente (segundos)
    }
  end

  @doc """
  Retorna a configuração de paginação para carregamento de mensagens antigas.
  """
  def pagination_config do
    %{
      default_limit: 20,         # Número padrão de mensagens por página
      max_limit: 50,             # Limite máximo de mensagens por página
      max_offset: 1000           # Offset máximo para evitar consultas muito antigas
    }
  end

  @doc """
  Retorna configurações de performance para o chat.
  """
  def performance_config do
    %{
      message_cache_size: 1000,  # Tamanho do cache de mensagens em memória
      presence_update_interval: 30_000,  # Intervalo de atualização de presença (ms)
      typing_timeout: 5000       # Timeout para indicador de digitação (ms)
    }
  end

  @doc """
  Retorna configurações de segurança para o chat.
  """
  def security_config do
    %{
      max_message_length: 1000,  # Comprimento máximo de uma mensagem
      rate_limit_messages: 10,   # Máximo de mensagens por minuto por usuário
      rate_limit_window: 60      # Janela de tempo para rate limiting (segundos)
    }
  end

  @doc """
  Retorna configurações de notificação para o chat.
  """
  def notification_config do
    %{
      enable_sound: true,        # Habilitar som para novas mensagens
      enable_desktop_notifications: true,  # Habilitar notificações desktop
      notification_timeout: 5000  # Tempo de exibição da notificação (ms)
    }
  end

  @doc """
  Retorna configurações de UI/UX para o chat.
  """
  def ui_config do
    %{
      auto_scroll_enabled: true,  # Habilitar scroll automático para novas mensagens
      show_timestamps: true,      # Mostrar timestamps nas mensagens
      show_user_avatars: true,    # Mostrar avatares dos usuários
      message_grouping_timeout: 300_000  # Agrupar mensagens do mesmo usuário (5 min)
    }
  end

  @doc """
  Retorna configurações de desenvolvimento/debug.
  """
  def debug_config do
    %{
      enable_debug_logs: false,   # Habilitar logs de debug
      log_message_events: false,  # Logar eventos de mensagens
      log_presence_events: false, # Logar eventos de presença
      log_performance_metrics: false  # Logar métricas de performance
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
