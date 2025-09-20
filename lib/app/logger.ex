defmodule App.Logger do
  @moduledoc """
  Módulo para logging estruturado e seguro em produção.

  Fornece funções para logging com diferentes níveis de verbosidade
  e proteção contra vazamento de informações sensíveis.
  """

  require Logger

  @doc """
  Log de erro crítico do sistema.
  """
  def error(message, metadata \\ %{}) do
    Logger.error(message, sanitize_metadata(metadata))
  end

  @doc """
  Log de aviso para situações que precisam de atenção.
  """
  def warning(message, metadata \\ %{}) do
    Logger.warning(message, sanitize_metadata(metadata))
  end

  @doc """
  Log de informação para eventos importantes do sistema.
  """
  def info(message, metadata \\ %{}) do
    Logger.info(message, sanitize_metadata(metadata))
  end

  @doc """
  Log de debug (apenas em desenvolvimento).
  """
  def debug(message, metadata \\ %{}) do
    if Application.get_env(:logger, :level) == :debug do
      Logger.debug(message, sanitize_metadata(metadata))
    end
  end

  @doc """
  Log de eventos de autenticação.
  """
  def auth_event(event, user_id \\ nil, metadata \\ %{}) do
    safe_metadata =
      metadata
      |> Map.put(:event_type, "auth")
      |> Map.put(:event, event)
      |> maybe_put_user_id(user_id)

    Logger.info("Authentication event: #{event}", safe_metadata)
  end

  @doc """
  Log de eventos de chat.
  """
  def chat_event(event, order_id \\ nil, user_id \\ nil, metadata \\ %{}) do
    safe_metadata =
      metadata
      |> Map.put(:event_type, "chat")
      |> Map.put(:event, event)
      |> maybe_put_order_id(order_id)
      |> maybe_put_user_id(user_id)

    Logger.info("Chat event: #{event}", safe_metadata)
  end

  @doc """
  Log de eventos de sistema.
  """
  def system_event(event, metadata \\ %{}) do
    safe_metadata =
      metadata
      |> Map.put(:event_type, "system")
      |> Map.put(:event, event)

    Logger.info("System event: #{event}", safe_metadata)
  end

  # Funções privadas

  defp sanitize_metadata(metadata) do
    metadata
    |> remove_sensitive_keys()
    |> truncate_long_values()
  end

  defp remove_sensitive_keys(metadata) do
    sensitive_keys = [:password, :token, :secret, :key, :auth_token, :session_token]

    Enum.reduce(sensitive_keys, metadata, fn key, acc ->
      Map.delete(acc, key)
    end)
  end

  defp truncate_long_values(metadata) do
    Enum.map(metadata, fn {key, value} ->
      case value do
        val when is_binary(val) and byte_size(val) > 100 ->
          {key, String.slice(val, 0, 100) <> "..."}
        val ->
          {key, val}
      end
    end)
    |> Enum.into(%{})
  end

  defp maybe_put_user_id(metadata, nil), do: metadata
  defp maybe_put_user_id(metadata, user_id), do: Map.put(metadata, :user_id, user_id)

  defp maybe_put_order_id(metadata, nil), do: metadata
  defp maybe_put_order_id(metadata, order_id), do: Map.put(metadata, :order_id, order_id)
end
