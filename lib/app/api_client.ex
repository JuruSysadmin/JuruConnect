defmodule App.ApiClient do
  @moduledoc """
  Cliente para consumir APIs externas
  """

  require Logger
  require :telemetry

  @base_url "http://10.1.1.212:8065/api/v1"

  def fetch_dashboard_summary do
    start_time = System.monotonic_time(:millisecond)
    with {:ok, sale_data} <- fetch_sale_data(),
         {:ok, company_result} <- fetch_companies_data() do
      summary = %{
        # Dados DIÁRIOS (da API /dashboard/sale)
        "sale" => Map.get(sale_data, "sale", 0.0),
        "cost" => Map.get(sale_data, "cost", 0.0),
        "devolution" => Map.get(sale_data, "devolution", 0.0),
        "objetivo" => Map.get(sale_data, "objetivo", 0.0),
        "profit" => Map.get(sale_data, "profit", 0.0),
        "percentual" => Map.get(sale_data, "percentual", 0.0),
        "nfs" => Map.get(sale_data, "nfs", 0),

        # Dados MENSAIS (da API /dashboard/sale/company)
        "percentualSale" => Map.get(company_result, :percentualSale, 0.0),
        "sale_mensal" => Map.get(company_result, :sale, 0.0),
        "objetivo_mensal" => Map.get(company_result, :objetive, 0.0),
        "devolution_mensal" => Map.get(company_result, :devolution, 0.0),
        "nfs_mensal" => Map.get(company_result, :nfs, 0)
      }
      duration = System.monotonic_time(:millisecond) - start_time
      Logger.info("fetch_dashboard_summary success", api: "dashboard_summary", status: :ok, duration_ms: duration)
      :telemetry.execute([:app, :api, :dashboard_summary], %{duration: duration}, %{status: :ok})
      {:ok, summary}
    else
      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("fetch_dashboard_summary error", api: "dashboard_summary", status: :error, duration_ms: duration, error: inspect(reason))
        :telemetry.execute([:app, :api, :dashboard_summary], %{duration: duration}, %{status: :error, error: inspect(reason)})
        {:error, reason}
    end
  end

  defp fetch_sale_data do
    url = "#{@base_url}/dashboard/sale"

    timeout_opts = [timeout: App.Config.api_timeout_ms(), recv_timeout: App.Config.api_timeout_ms()]
    case HTTPoison.get(url, [], timeout_opts) do
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

  def fetch_sales_feed_robust(desired_limit \\ nil) do
    actual_limit = desired_limit || App.Config.sales_feed_limit()

         case fetch_sales_feed_with_limit(actual_limit) do
      {:ok, [_ | _] = sales} ->
        {:ok, sales}

             _ ->
         fetch_sales_incremental()
    end
  end

  defp fetch_sales_feed_with_limit(limit) do
    url = "#{App.Config.api_urls().sales_feed}/#{limit}"

    timeout_opts = [timeout: App.Config.api_timeout_ms(), recv_timeout: App.Config.api_timeout_ms()]
    start_time = System.monotonic_time(:millisecond)
    case HTTPoison.get(url, [], timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} when is_map(data) ->
            sales_data = Map.get(data, "saleSupervisor", [])
            formatted_sales =
              sales_data
              |> Stream.map(&format_sale_supervisor/1)
              |> Enum.to_list()
            duration = System.monotonic_time(:millisecond) - start_time
            Logger.info("fetch_sales_feed_with_limit success", api: "sales_feed", status: :ok, duration_ms: duration, limit: limit)
            :telemetry.execute([:app, :api, :sales_feed], %{duration: duration}, %{status: :ok, limit: limit})
            {:ok, formatted_sales}

          {:ok, _} ->
            duration = System.monotonic_time(:millisecond) - start_time
            Logger.error("fetch_sales_feed_with_limit invalid format", api: "sales_feed", status: :error, duration_ms: duration, limit: limit)
            :telemetry.execute([:app, :api, :sales_feed], %{duration: duration}, %{status: :error, limit: limit, error: "invalid_format"})
            {:error, "Formato de dados inválido"}

          {:error, error} ->
            duration = System.monotonic_time(:millisecond) - start_time
            Logger.error("fetch_sales_feed_with_limit decode error", api: "sales_feed", status: :error, duration_ms: duration, limit: limit, error: inspect(error))
            :telemetry.execute([:app, :api, :sales_feed], %{duration: duration}, %{status: :error, limit: limit, error: inspect(error)})
            {:error, "Erro ao decodificar JSON: #{inspect(error)}"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("fetch_sales_feed_with_limit status error", api: "sales_feed", status: :error, duration_ms: duration, limit: limit, status_code: status_code)
        :telemetry.execute([:app, :api, :sales_feed], %{duration: duration}, %{status: :error, limit: limit, status_code: status_code})
        {:error, "API retornou status #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("fetch_sales_feed_with_limit http error", api: "sales_feed", status: :error, duration_ms: duration, limit: limit, error: inspect(reason))
        :telemetry.execute([:app, :api, :sales_feed], %{duration: duration}, %{status: :error, limit: limit, error: inspect(reason)})
        {:error, "Erro de conexão: #{inspect(reason)}"}
    end
  end

  def fetch_sales_feed(limit \\ nil) do
    fetch_sales_feed_robust(limit)
  end

     defp fetch_sales_incremental do
     limits_to_try = [30, 25, 20, 15, 10]

    Enum.reduce_while(limits_to_try, {:error, "Nenhum limite funcionou"}, fn limit, _acc ->
      case fetch_sales_feed_with_limit(limit) do
        {:ok, [_ | _] = sales} ->
          {:halt, {:ok, sales}}
        _ ->
          {:cont, {:error, "Limite #{limit} falhou"}}
      end
    end)
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

  def fetch_companies_data do
    url = "http://10.1.1.212:8065/api/v1/dashboard/sale/company"

    timeout_opts = [timeout: App.Config.api_timeout_ms(), recv_timeout: App.Config.api_timeout_ms()]
    start_time = System.monotonic_time(:millisecond)
    case HTTPoison.get(url, [], timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.info("fetch_companies_data success", api: "companies_data", status: :ok, duration_ms: duration)
        :telemetry.execute([:app, :api, :companies_data], %{duration: duration}, %{status: :ok})
        process_companies_response(body)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("fetch_companies_data status error", api: "companies_data", status: :error, duration_ms: duration, status_code: status_code)
        :telemetry.execute([:app, :api, :companies_data], %{duration: duration}, %{status: :error, status_code: status_code})
        {:error, "API retornou status #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("fetch_companies_data http error", api: "companies_data", status: :error, duration_ms: duration, error: inspect(reason))
        :telemetry.execute([:app, :api, :companies_data], %{duration: duration}, %{status: :error, error: inspect(reason)})
        {:error, "Erro de conexão: #{inspect(reason)}"}
    end
  end

  defp process_companies_response(body) do
        case Jason.decode(body) do
          {:ok, data} when is_map(data) ->
            companies_data = Map.get(data, "saleSupervisor", [])

            companies =
              companies_data
              |> Stream.map(fn company ->
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
              |> Enum.to_list()

            result = %{
              companies: companies,
              percentualSale: Map.get(data, "percentualSale", 0.0),
              # Dados do nível raiz da API (MENSAIS)
              objetive: Map.get(data, "objetive", 0.0),
              sale: Map.get(data, "sale", 0.0),
              devolution: Map.get(data, "devolution", 0.0),
              nfs: Map.get(data, "nfs", 0)
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

  @doc """
  Busca os dados de saleSupervisor para um supervisor específico.
  """
  def fetch_supervisor_data(supervisor_id) do
    url = "http://10.1.1.108:8065/api/v1/dashboard/sale/#{supervisor_id}"
    timeout_opts = [recv_timeout: 5_000]
    case HTTPoison.get(url, [], timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"saleSupervisor" => sale_supervisors}} -> {:ok, sale_supervisors}
          {:ok, _} -> {:ok, []}
          _ -> {:error, :invalid_json}
        end
      _ ->
        {:error, :api_error}
    end
  end


end
