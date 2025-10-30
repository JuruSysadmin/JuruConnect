defmodule App.Config do
  @moduledoc """
  Configurações centralizadas da aplicação.

  Centraliza todas as configurações de limites, URLs e parâmetros
  para facilitar manutenção e ajustes.
  """

  @type api_key ::
          :dashboard_base
          | :dashboard_sale
          | :dashboard_companies
          | :dashboard_seller
          | :dashboard_schedule
          | :dashboard_returns

  @doc """
  Retorna a URL base da API do dashboard.

  Ordem de resolução (da maior para a menor prioridade):
  - System env `DASHBOARD_BASE_URL`
  - Config `:app, :dashboard_base_url`
  - Default local
  """
  @spec dashboard_base_url() :: String.t()
  def dashboard_base_url do
    System.get_env("DASHBOARD_BASE_URL") ||
      Application.get_env(:app, :dashboard_base_url) ||
      "http://10.1.1.168:8065/api/v1"
  end

  @doc """
  Retorna todas as URLs utilizadas na aplicação.

  Mantém compatibilidade com chamadas existentes.
  """
  @spec api_urls() :: %{required(api_key()) => String.t()}
  def api_urls do
    base = dashboard_base_url()

    %{
      dashboard_base: base,
      dashboard_sale: join_url(base, "/dashboard/sale"),
      dashboard_companies: join_url(base, "/dashboard/sale/company"),
      dashboard_seller: join_url(base, "/dashboard/sale"),
      dashboard_schedule: join_url(base, "/shipping/schedule"),
      dashboard_returns: join_url(base, "/dashboard/returns/by-day")
    }
  end

  @doc """
  Retorna uma URL específica por chave.
  """
  @spec api_url(api_key()) :: String.t()
  def api_url(key) do
    Map.fetch!(api_urls(), key)
  end

  @doc """
  Timeout de chamadas à API em milissegundos.
  """
  @spec api_timeout_ms() :: non_neg_integer()
  def api_timeout_ms do
    Application.get_env(:app, :api_timeout_ms, 10_000)
  end

  # Junta base + path garantindo apenas uma barra entre as partes
  @spec join_url(String.t(), String.t()) :: String.t()
  defp join_url(base, path) do
    base = String.trim_trailing(base, "/")
    path = "/" <> String.trim_leading(path, "/")
    base <> path
  end
end
