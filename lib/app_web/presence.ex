defmodule AppWeb.Presence do
  @moduledoc """
  Módulo de presença para tracking de usuários online em tempo real.

  Otimizado para notificações rápidas de entrada/saída com menor latência.
  """
  use Phoenix.Presence,
    otp_app: :app,
    pubsub_server: App.PubSub

  @spec init(any) :: {:ok, map}
  def init(_opts) do
    # Configurações de presença para detecção rápida
    {:ok, %{
      # Intervalo de heartbeat em milissegundos
      heartbeat_interval: 1_000,  # 1 segundo (padrão: 30s)
      # Tempo limite para considerar cliente offline em milissegundos
      max_age: 3_000,             # 3 segundos (padrão: 60s)
      # Intervalo de limpeza de clientes inativos em milissegundos
      gc_interval: 2_000          # 2 segundos (padrão: 30s)
    }}
  end

  @spec fetch(String.t(), map) :: map
  def fetch(_topic, presences) when is_map(presences) do
    # Retorna presences sem modificação
    presences
  end

  @spec fetch(String.t(), any) :: map
  def fetch(_topic, _presences) do
    # Retorna mapa vazio para dados inválidos
    %{}
  end
end
