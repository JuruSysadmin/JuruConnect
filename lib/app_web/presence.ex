defmodule AppWeb.Presence do
  @moduledoc """
  Módulo de presença para tracking de usuários online em tempo real.

  Otimizado para notificações rápidas de entrada/saída com menor latência.
  """
  use Phoenix.Presence,
    otp_app: :app,
    pubsub_server: App.PubSub

  def init(_opts) do
    # Configurações otimizadas para menor latência
    {:ok, %{
      # Reduzir intervalo de heartbeat para detecção mais rápida
      heartbeat_interval: 1_000,  # 1 segundo (padrão: 30s)
      # Tempo limite para considerar cliente offline
      max_age: 3_000,             # 3 segundos (padrão: 60s)
      # Frequência de limpeza de clientes inativos
      gc_interval: 2_000          # 2 segundos (padrão: 30s)
    }}
  end

  def fetch(_topic, presences) do
    # Otimização: retorna presences como estão para reduzir processamento
    presences
  end
end
