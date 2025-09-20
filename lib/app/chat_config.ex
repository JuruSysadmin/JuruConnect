defmodule App.ChatConfig do
  @moduledoc """
  Centralized configuration for the chat system.

  Provides type-safe access to all chat-related settings including message limits,
  timeouts, circuit breakers, and performance tuning parameters. This module
  ensures consistent configuration across the entire chat system.
  """

  @doc """
  Default number of messages to load when entering a chat room.

  Balances performance with user experience by providing recent context
  without overwhelming the client with too much data.
  """
  def default_message_limit, do: 50

  @doc """
  Maximum number of messages that can be loaded in a single request.

  Prevents abuse and ensures system stability by limiting the amount
  of data transferred in a single operation.
  """
  def max_message_limit, do: 100

  @doc """
  Fallback username when the real user name cannot be determined.

  Used to maintain a consistent user experience even when user data
  is temporarily unavailable or incomplete.
  """
  def default_username, do: "Usuário"

  @doc """
  Room inactivity timeout in minutes before automatic cleanup.

  Prevents resource leaks by automatically closing unused chat rooms
  and freeing up system resources for active conversations.
  """
  def room_inactivity_timeout, do: 30

  @doc """
  Circuit breaker configuration for link preview service.

  Protects the system from cascading failures when external link preview
  services are unavailable or responding slowly.
  """
  def link_preview_circuit_breaker do
    %{
      max_failures: 5,
      failure_period_s: 60,
      reset_period_s: 300
    }
  end

  @doc """
  Pagination configuration for loading historical messages.

  Controls how messages are loaded in batches to optimize performance
  and prevent excessive database queries for very old conversations.
  """
  def pagination_config do
    %{
      default_limit: 20,
      max_limit: 50,
      max_offset: 1000
    }
  end

  @doc """
  Performance tuning configuration for chat operations.

  Optimizes system performance through caching strategies and
  controlled update intervals to balance responsiveness with resource usage.
  """
  def performance_config do
    %{
      message_cache_size: 1000,
      presence_update_interval: 30_000,
      typing_timeout: 5000
    }
  end

  @doc """
  Security configuration for chat message handling.

  Implements rate limiting and content validation to prevent abuse
  and ensure system stability under high load conditions.
  """
  def security_config do
    %{
      max_message_length: 1000,
      rate_limit_messages: 10,
      rate_limit_window: 60
    }
  end

  @doc """
  Notification preferences for chat interactions.

  Controls user notification behavior including sound alerts and
  desktop notifications to enhance user engagement.
  """
  def notification_config do
    %{
      enable_sound: true,
      enable_desktop_notifications: true,
      notification_timeout: 5000
    }
  end

  @doc """
  User interface and experience configuration.

  Defines visual behavior and interaction patterns to create
  an intuitive and responsive chat interface.
  """
  def ui_config do
    %{
      auto_scroll_enabled: true,
      show_timestamps: true,
      show_user_avatars: true,
      message_grouping_timeout: 300_000
    }
  end

  @doc """
  Development and debugging configuration.

  Controls logging verbosity and diagnostic features to aid
  development and troubleshooting without impacting production performance.
  """
  def debug_config do
    %{
      enable_debug_logs: false,
      log_message_events: false,
      log_presence_events: false,
      log_performance_metrics: false
    }
  end

  @doc """
  Returns all configuration settings as a structured map.

  Provides a complete view of all chat system settings for
  administrative interfaces and system monitoring tools.
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
