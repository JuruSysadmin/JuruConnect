defmodule AppWeb.DashboardState do
  @moduledoc """
  Módulo para gerenciar estado compartilhado do dashboard.

  Centraliza funções comuns para processamento de dados,
  conversão de chaves e formatação de valores.
  """

  import AppWeb.DashboardUtils

  @brazil_timezone "America/Sao_Paulo"

  @doc """
  Converte chaves de string para átomos de forma segura.
  """
  def convert_keys_to_atoms(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> convert_key_to_atom(k, v) end)
    |> Enum.into(%{})
  end

  def convert_keys_to_atoms(_), do: %{}

  defp convert_key_to_atom(k, v) when is_binary(k) do
    {String.to_existing_atom(k), v}
  rescue
    ArgumentError -> {k, v}
  end

  defp convert_key_to_atom(k, v), do: {k, v}

  @doc """
  Processa dados das empresas com animações.
  """
  def process_companies_with_animation(data, previous_lojas_map) do
    companies = get_companies_data(data)

    Enum.map(companies, fn loja ->
      previous_value = Map.get(previous_lojas_map, loja.supervisor_id, 0.0)
      increment = loja.venda_dia - previous_value
      animate_venda_dia = increment > 0 and previous_value > 0

      loja
      |> Map.put(:animate_venda_dia, animate_venda_dia)
      |> Map.put(:increment_value, increment)
    end)
  end

  @doc """
  Extrai dados das empresas do payload da API.
  """
  def get_companies_data(%{companies: companies}) when is_list(companies), do: companies
  def get_companies_data(_), do: []

  @doc """
  Cria mapa de dados anteriores das lojas para comparação.
  """
  def create_previous_lojas_map(companies) do
    Map.new(companies, fn loja -> {loja.supervisor_id, loja.venda_dia} end)
  end

  @doc """
  Calcula valores de template para métricas mensais.
  Permite valores acima de 100% para indicar excedente.
  """
  def calculate_monthly_template_values(percentual_sale, monthly_sale_value, monthly_goal_value) do
    remaining = monthly_goal_value - monthly_sale_value

    %{
      percentual_sale_display: format_percent(percentual_sale),
      percentual_sale_capped: percentual_sale, # Removed cap to allow > 100%
      goal_remaining_display: format_money(abs(remaining)),
      goal_exceeded: remaining < 0,
      show_goal_remaining: monthly_sale_value > 0 and monthly_goal_value > 0
    }
  end

  @doc """
  Detecta animações baseadas em mudanças de valores.
  """
  def detect_animations(current_value, previous_value) do
    current_value > previous_value and previous_value > 0
  end

  @doc """
  Detecta animação de profit (margem).
  """
  def detect_profit_animation(current_profit, previous_profit) do
    cond do
      current_profit > previous_profit and previous_profit != 0.0 -> :up
      current_profit < previous_profit and previous_profit != 0.0 -> :down
      true -> nil
    end
  end

  @doc """
  Obtém timestamp atual no timezone do Brasil.
  """
  def get_brazil_timestamp do
    Timex.Timezone.convert(DateTime.utc_now(), @brazil_timezone)
  end

  @doc """
  Cria estrutura de dados padrão para métricas diárias.
  """
  def create_daily_metrics_data(data) do
    %{
      sale: format_money(Map.get(data, :sale, 0.0)),
      cost: format_money(Map.get(data, :cost, 0.0)),
      devolution: format_money(Map.get(data, :devolution, 0.0)),
      objetivo: format_money(Map.get(data, :objetivo, 0.0)),
      profit: format_percent(Map.get(data, :profit, 0.0)),
      percentual: format_percent(Map.get(data, :percentual, 0.0)),
      percentual_num: calculate_percentual_number(data),
      invoices_count: trunc(Map.get(data, :nfs, 0)),
      sale_value: Map.get(data, :sale, 0.0),
      goal_value: Map.get(data, :objetivo, 0.0),
      ticket_medio_diario: format_money(Map.get(data, :ticket_medio_diario, 0.0)),
      ticket_medio_mensal: format_money(Map.get(data, :ticket_medio_mensal, 0.0)),
      percentual_objetivo_hora_formatted: format_percent(Map.get(data, :percentual_objetivo_hora, 0.0))
    }
  end

  @doc """
  Cria estrutura de dados padrão para métricas mensais.
  """
  def create_monthly_metrics_data(data) do
    %{
      sale_mensal: format_money(Map.get(data, :sale_mensal, 0.0)),
      objetivo_mensal: format_money(Map.get(data, :objetivo_mensal, 0.0)),
      devolution_mensal: format_money(Map.get(data, :devolution_mensal, 0.0)),
      monthly_invoices_count: trunc(Map.get(data, :nfs_mensal, 0)),
      percentual_sale: Map.get(data, :percentualSale, 0.0),
      monthly_sale_value: Map.get(data, :sale_mensal, 0.0),
      monthly_goal_value: Map.get(data, :objetivo_mensal, 0.0)
    }
  end

  @doc """
  Cria estrutura de dados padrão para estado de erro.
  """
  def create_error_state_data(previous_values \\ %{}) do
    Map.merge(%{
      sale: "R$ 0,00",
      cost: "R$ 0,00",
      devolution: "R$ 0,00",
      objetivo: "R$ 0,00",
      profit: "0,00%",
      percentual: "0,00%",
      percentual_num: 0,
      invoices_count: 0,
      sale_value: 0.0,
      goal_value: 0.0,
      ticket_medio_diario: "R$ 0,00",
      ticket_medio_mensal: "R$ 0,00",
      percentual_objetivo_hora_formatted: "0,00%",
      diff_today_formatted: "R$ 0,00",
      diff_today_title: "Diferença para Meta Dia",
      show_diff_today: false,
      sale_mensal: "R$ 0,00",
      objetivo_mensal: "R$ 0,00",
      devolution_mensal: "R$ 0,00",
      monthly_invoices_count: 0,
      percentual_sale: 0,
      monthly_sale_value: 0.0,
      monthly_goal_value: 0.0,
      goal_exceeded: false,
      lojas_data: [],
      animate_sale: false,
      animate_devolution: false,
      animate_profit: nil
    }, previous_values)
  end
end
