defmodule App.ApiClient do
  @moduledoc """
  Cliente para consumir APIs externas
  """

  def fetch_dashboard_summary do
    start_time = System.monotonic_time(:millisecond)
    with {:ok, sale_data} <- fetch_sale_data(),
         {:ok, company_result} <- fetch_companies_data() do
      # Calcula ticket médio mensal de todas as lojas
      ticket_medio_mensal = calculate_average_ticket(company_result)

      # Calcula ticket médio diário (baseado em vendas e NF's do dia)
      ticket_medio_diario = calculate_daily_ticket(company_result)

      summary = %{
        "sale" => Map.get(sale_data, "sale", 0.0),
        "cost" => Map.get(sale_data, "cost", 0.0),
        "devolution" => Map.get(sale_data, "devolution", 0.0),
        "objetivo" => Map.get(sale_data, "objetivo", 0.0),
        "profit" => Map.get(sale_data, "profit", 0.0),
        "percentual" => Map.get(sale_data, "percentual", 0.0),
        "nfs" => Map.get(sale_data, "nfs", 0),
        "percentualSale" => Map.get(company_result, :percentualSale, 0.0),
        "sale_mensal" => Map.get(company_result, :sale, 0.0),
        "objetivo_mensal" => Map.get(company_result, :objetive, 0.0),
        "devolution_mensal" => Map.get(company_result, :devolution, 0.0),
        "nfs_mensal" => Map.get(company_result, :nfs, 0),
        "ticket_medio_mensal" => ticket_medio_mensal,
        "ticket_medio_diario" => ticket_medio_diario
      }
      duration = System.monotonic_time(:millisecond) - start_time
      :telemetry.execute([:app, :api, :dashboard_summary], %{duration: duration}, %{status: :ok})
      {:ok, summary}
    else
      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start_time
        :telemetry.execute([:app, :api, :dashboard_summary], %{duration: duration}, %{status: :error, error: inspect(reason)})
        {:error, reason}
    end
  end

  defp fetch_sale_data do
    url = App.Config.api_urls().dashboard_sale

    with {:ok, body} <- http_get(url, "dashboard_sale") do
      decode_json(body)
    end
  end

  def fetch_companies_data do
    url = App.Config.api_urls().dashboard_companies

    with {:ok, body} <- http_get(url, "companies_data") do
      process_companies_response(body)
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
              devolution: Map.get(company, "devolution", 0.0),
              pre_sale_qtde: Map.get(company, "preSaleQtde", 0),
              status: determine_status(company)
            }
          end)

        perc_list = Enum.map(companies, & &1.perc_hora)
        avg_percentual_obj_hour =
          if perc_list == [], do: 0.0, else: Enum.sum(perc_list) / length(perc_list)

        result = %{
          companies: companies,
          percentualSale: Map.get(data, "percentualSale", 0.0),
          objetive: Map.get(data, "objetive", 0.0),
          sale: Map.get(data, "sale", 0.0),
          devolution: Map.get(data, "devolution", 0.0),
          nfs: Map.get(data, "nfs", 0),
          percentual_objetivo_hora: avg_percentual_obj_hour
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
    calculate_daily_percentage(venda_hoje, objetivo_hoje)
  end

  defp calculate_daily_percentage(_venda_hoje, objetivo_hoje) when objetivo_hoje <= 0, do: 0.0
  defp calculate_daily_percentage(venda_hoje, objetivo_hoje), do: venda_hoje / objetivo_hoje * 100

  defp determine_status(company) do
    perc_hora = Map.get(company, "percentualObjectiveHour", 0.0)
    venda_hoje = Map.get(company, "saleToday", 0.0)
    determine_status_by_metrics(venda_hoje, perc_hora)
  end

  defp determine_status_by_metrics(venda_hoje, _perc_hora) when venda_hoje == 0, do: :sem_vendas
  defp determine_status_by_metrics(_venda_hoje, perc_hora) when perc_hora >= 100, do: :atingida_hora
  defp determine_status_by_metrics(_venda_hoje, _perc_hora), do: :abaixo_meta

  @doc """
  Busca os dados de saleSupervisor para um supervisor específico.
  """
  def fetch_supervisor_data(supervisor_id) do
    base_url = App.Config.api_urls().dashboard_seller
    url = "#{base_url}/#{supervisor_id}"

    with {:ok, body} <- http_get(url, "supervisor_data", timeout: 5_000),
         {:ok, data} <- decode_json(body) do
      sale_supervisors = Map.get(data, "saleSupervisor", [])
      {:ok, sale_supervisors}
    end
  end

  @doc """
  Busca os dados de agendamento de entregas.
  """
  def fetch_schedule_data do
    url = App.Config.api_urls().dashboard_schedule

    with {:ok, body} <- http_get(url, "schedule_data", timeout: 5_000) do
      decode_json(body)
    end
  end

  # Função genérica para requisições HTTP com telemetria
  defp http_get(url, api_name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, App.Config.api_timeout_ms())
    timeout_opts = [timeout: timeout, recv_timeout: timeout]
    start_time = System.monotonic_time(:millisecond)

    case HTTPoison.get(url, [], timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        :telemetry.execute([:app, :api, String.to_atom(api_name)], %{duration: duration}, %{status: :ok})
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        :telemetry.execute([:app, :api, String.to_atom(api_name)], %{duration: duration}, %{status: :error, status_code: status_code})
        {:error, "API retornou status #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        :telemetry.execute([:app, :api, String.to_atom(api_name)], %{duration: duration}, %{status: :error, error: inspect(reason)})
        {:error, "Erro de conexão: #{inspect(reason)}"}
    end
  end

  # Função genérica para decodificar JSON
  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, error} -> {:error, "Erro ao decodificar JSON: #{inspect(error)}"}
    end
  end

  # Calcula o ticket médio mensal de todas as lojas
  defp calculate_average_ticket(company_result) do
    companies = Map.get(company_result, :companies, [])

    case companies do
      [] -> 0.0
      companies ->
        total_tickets = Enum.reduce(companies, 0.0, fn company, acc ->
          ticket = Map.get(company, :ticket, 0.0)
          acc + ticket
        end)

        if length(companies) > 0 do
          total_tickets / length(companies)
        else
          0.0
        end
    end
  end

  # Calcula o ticket médio diário baseado em vendas e NF's do dia
  defp calculate_daily_ticket(company_result) do
    companies = Map.get(company_result, :companies, [])

    case companies do
      [] -> 0.0
      companies ->
        {total_vendas, total_nfs} = Enum.reduce(companies, {0.0, 0}, fn company, {vendas_acc, nfs_acc} ->
          venda_dia = Map.get(company, :venda_dia, 0.0)
          qtde_nfs = Map.get(company, :qtde_nfs, 0)
          {vendas_acc + venda_dia, nfs_acc + qtde_nfs}
        end)

        if total_nfs > 0 do
          total_vendas / total_nfs
        else
          0.0
        end
    end
  end

end
