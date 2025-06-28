defmodule App.ApiClient do
  @moduledoc """
  Cliente para consumir APIs externas
  """

  @base_url "http://10.1.1.212:8065/api/v1"

  @doc """
  Busca dados resumidos do dashboard
  """
  def fetch_dashboard_summary do
    with {:ok, sale_data} <- fetch_sale_data(),
         {:ok, company_result} <- fetch_companies_data() do
      summary = %{
        "sale" => Map.get(sale_data, "sale", 0.0),
        "cost" => Map.get(sale_data, "cost", 0.0),
        "devolution" => Map.get(sale_data, "devolution", 0.0),
        "objetivo" => Map.get(sale_data, "objetivo", 0.0),
        "profit" => Map.get(sale_data, "profit", 0.0),
        "percentual" => Map.get(sale_data, "percentual", 0.0),
        "percentualSale" => Map.get(company_result, :percentualSale, 0.0),
        "nfs" => Map.get(sale_data, "nfs", 0)
      }

      {:ok, summary}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_sale_data do
    url = "#{@base_url}/dashboard/sale"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, error} -> {:error, "Erro ao decodificar JSON: #{inspect(error)}"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "API retornou status #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Erro de conexão: #{inspect(reason)}"}
    end
  end

  @doc """
  Busca dados do feed de vendas em tempo real
  """
  def fetch_sales_feed(limit \\ 15) do
    url = "http://vendaweb.jurunense.com.br/api/v1/dashboard/sale/#{limit}"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} when is_map(data) ->
            sales_data = Map.get(data, "saleSupervisor", [])
            formatted_sales = Enum.map(sales_data, &format_sale_supervisor/1)
            {:ok, formatted_sales}

          {:ok, _} ->
            {:error, "Formato de dados inválido"}

          {:error, error} ->
            {:error, "Erro ao decodificar JSON: #{inspect(error)}"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "API retornou status #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Erro de conexão: #{inspect(reason)}"}
    end
  end

  defp format_sale_supervisor(sale_data) do
    sale_value = Map.get(sale_data, "saleValue", 0.0)
    objetivo = Map.get(sale_data, "objetivo", 0.0)

    %{
      id: System.unique_integer([:positive]),
      seller_name: Map.get(sale_data, "sellerName", "Vendedor Desconhecido"),
      store: Map.get(sale_data, "store", "Loja Não Informada"),
      sale_value: normalize_decimal(sale_value),
      objetivo: normalize_decimal(objetivo),
      timestamp: DateTime.utc_now(),
      type: :sale_supervisor
    }
  end

  defp normalize_decimal(value) when is_float(value), do: Float.round(value, 2)
  defp normalize_decimal(value) when is_integer(value), do: Float.round(value * 1.0, 2)

  defp normalize_decimal(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> Float.round(num, 2)
      :error -> 0.0
    end
  end

  defp normalize_decimal(nil), do: 0.0
  defp normalize_decimal(_), do: 0.0

  @doc """
  Busca dados das lojas/companies do dashboard
  """
  def fetch_companies_data do
    url = "http://10.1.1.212:8065/api/v1/dashboard/sale/company"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        process_companies_response(body)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "API retornou status #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Erro de conexão: #{inspect(reason)}"}
    end
  end

  defp process_companies_response(body) do
        case Jason.decode(body) do
          {:ok, data} when is_map(data) ->
            companies_data = Map.get(data, "saleSupervisor", [])

            companies =
              Enum.map(companies_data, fn company ->
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

            result = %{
              companies: companies,
              percentualSale: Map.get(data, "percentualSale", 0.0)
            }

            {:ok, result}

          {:ok, _} ->
            {:error, "Formato de dados inválido"}

          {:error, error} ->
            {:error, "Erro ao decodificar JSON: #{inspect(error)}"}
    end
  end

  defp calculate_daily_percentage(company) do
    objetivo_hoje = Map.get(company, "objetiveToday", 0.0)
    venda_hoje = Map.get(company, "saleToday", 0.0)

    if objetivo_hoje > 0 do
      venda_hoje / objetivo_hoje * 100
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
