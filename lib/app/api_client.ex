defmodule App.ApiClient do
  @moduledoc """
  Cliente para consumir APIs externas
  """

  alias HTTPoison.Response
  alias HTTPoison.Error

  @base_url "http://10.1.1.212/api/v1"

  @doc """
  Busca dados resumidos do dashboard
  """
  def fetch_dashboard_summary do
    url = "#{@base_url}/dashboard/sale"
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            # Extrai apenas os campos desejados
            summary = %{
              "sale" => Map.get(data, "sale", 0.0),
              "cost" => Map.get(data, "cost", 0.0),
              "devolution" => Map.get(data, "devolution", 0.0),
              "objetivo" => Map.get(data, "objetivo", 0.0),
              "profit" => Map.get(data, "profit", 0.0),
              "percentual" => Map.get(data, "percentual", 0.0),
              "nfs" => Map.get(data, "nfs", 0)
            }
            {:ok, summary}
          {:error, error} -> {:error, "Erro ao decodificar JSON: #{inspect(error)}"}
        end
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "API retornou status #{status_code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Erro de conexão: #{inspect(reason)}"}
    end
  end

  @doc """
  Busca dados das lojas/companies do dashboard
  """
  def fetch_companies_data do
    url = "http://10.1.1.212:8065/api/v1/dashboard/sale/company"
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} when is_map(data) ->
            # Os dados das lojas estão no campo "saleSupervisor"
            companies_data = Map.get(data, "saleSupervisor", [])
            companies = Enum.map(companies_data, fn company ->
              %{
                supervisor_id: Map.get(company, "supervisorId"),
                nome: Map.get(company, "store", ""),
                meta_dia: Map.get(company, "objetiveToday", 0.0),
                meta_hora: Map.get(company, "objetiveHour", 0.0),
                qtde_nfs: Map.get(company, "qtdeInvoiceDay", 0),
                venda_dia: Map.get(company, "saleToday", 0.0),
                perc_hora: Map.get(company, "percentualObjectiveHour", 0.0),
                perc_dia: calculate_daily_percentage(company),
                objetivo_mes: Map.get(company, "objetivo", 0.0),
                venda_mes: Map.get(company, "saleValue", 0.0),
                percentual_mes: Map.get(company, "percentualObjective", 0.0),
                ticket: Map.get(company, "ticket", 0.0),
                mix: Map.get(company, "mix", 0),
                status: determine_status(company)
              }
            end)
            {:ok, companies}
          {:ok, _} -> {:error, "Formato de dados inválido"}
          {:error, error} -> {:error, "Erro ao decodificar JSON: #{inspect(error)}"}
        end
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "API retornou status #{status_code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Erro de conexão: #{inspect(reason)}"}
    end
  end

  defp calculate_daily_percentage(company) do
    objetivo_hoje = Map.get(company, "objetiveToday", 0.0)
    venda_hoje = Map.get(company, "saleToday", 0.0)

    if objetivo_hoje > 0 do
      (venda_hoje / objetivo_hoje) * 100
    else
      0.0
    end
  end

  defp determine_status(company) do
    perc_hora = Map.get(company, "percentualObjectiveHour", 0.0)
    venda_hoje = Map.get(company, "saleToday", 0.0)

    cond do
      venda_hoje == 0 -> :sem_vendas
      perc_hora >= 100 -> :atingida_hora
      true -> :abaixo_meta
    end
  end
end
