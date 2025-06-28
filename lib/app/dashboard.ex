defmodule App.Dashboard do
  @moduledoc """
  Context para operações do Dashboard.

  Este módulo centraliza toda a lógica de negócio relacionada ao dashboard,
  incluindo busca de dados, cálculos de métricas e formatação.
  """

  alias App.DashboardDataServer

  @doc """
  Busca e processa todos os dados necessários para o dashboard.

  ## Options

    * `:period` - Período dos dados (:today, :yesterday, :week, :month)
    * `:stores` - Lista de lojas específicas para filtrar
    * `:refresh` - Force refresh dos dados (default: false)

  ## Examples

      iex> App.Dashboard.get_metrics()
      {:ok, %{
        sales: %{total: 50000.0, formatted: "R$ 50.000,00"},
        goal: %{total: 60000.0, formatted: "R$ 60.000,00", percentage: 83.33},
        stores: [%{name: "Loja Centro", sales: 15000.0, goal_percentage: 75.0}]
      }}

      iex> App.Dashboard.get_metrics(period: :yesterday)
      {:ok, %{...}}
  """
  def get_metrics(opts \\ []) do
    with {:ok, raw_data} <- fetch_raw_data(opts),
         {:ok, processed_data} <- process_data(raw_data),
         {:ok, formatted_data} <- format_for_display(processed_data) do
      {:ok, formatted_data}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, "Erro inesperado: #{inspect(error)}"}
    end
  end

  @doc """
  Calcula métricas específicas de performance das lojas.
  """
  def get_store_performance(store_ids \\ []) do
    with {:ok, metrics} <- get_metrics(),
         stores_data <- filter_stores(metrics.stores, store_ids) do
      performance_data = calculate_store_performance(stores_data)
      {:ok, performance_data}
    end
  end

  @doc """
  Gera alertas baseados nas métricas atuais.
  """
  def get_alerts do
    case get_metrics() do
      {:ok, metrics} ->
        alerts = analyze_metrics_for_alerts(metrics)
        {:ok, alerts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Busca dados do feed de vendas em tempo real.
  """
  def get_sales_feed(limit \\ nil) do
    actual_limit = limit || App.Config.sales_feed_limit()

         case App.ApiClient.fetch_sales_feed_robust(actual_limit) do
      {:ok, sales_data} when length(sales_data) > 0 ->
        formatted_sales =
          sales_data
          |> Enum.map(&format_and_save_api_sale/1)
          |> Enum.sort_by(& &1.sale_value, :desc)

        {:ok, formatted_sales}

             _ ->
         try_fallback_strategies(actual_limit)
    end
  end

  defp try_fallback_strategies(actual_limit) do
    case App.Sales.get_sales_feed(actual_limit) do
      {:ok, [_ | _] = saved_sales} ->
        {:ok, saved_sales}

      _ ->
        case App.ApiClient.fetch_sales_feed(15) do
          {:ok, minimal_sales} ->
            formatted_minimal = Enum.map(minimal_sales, &format_and_save_api_sale/1)
            {:ok, formatted_minimal}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Registra uma nova venda no sistema.
  """
  def register_sale(sale_data) do
    with {:ok, validated_sale} <- validate_sale_data(sale_data),
         {:ok, saved_sale} <- save_sale(validated_sale),
         :ok <- broadcast_sale(saved_sale) do
      {:ok, saved_sale}
    end
  end

  @doc """
  Verifica se uma meta foi atingida e dispara celebração se necessário.
  """
  def check_goal_achievement(store_id) do
    with {:ok, store_metrics} <- get_store_metrics(store_id),
         true <- goal_achieved?(store_metrics),
         :ok <- trigger_celebration(store_metrics) do
      {:ok, :goal_achieved}
    else
      false -> {:ok, :goal_not_achieved}
      error -> error
    end
  end

  defp fetch_raw_data(_opts) do
    case DashboardDataServer.get_data() do
      %{api_status: :ok, data: data} when not is_nil(data) ->
        {:ok, data}

      %{api_status: status, api_error: error} ->
        {:error, "API Error (#{status}): #{error}"}

      _ ->
        {:error, "Dados não disponíveis"}
    end
  end

  defp process_data(raw_data) do
    processed = %{
      sales: extract_sales_data(raw_data),
      costs: extract_costs_data(raw_data),
      goals: extract_goals_data(raw_data),
      stores: extract_stores_data(raw_data),
      percentages: calculate_percentages(raw_data)
    }

    {:ok, processed}
  rescue
    error -> {:error, "Erro no processamento: #{inspect(error)}"}
  end

  defp format_for_display(processed_data) do
    formatted = %{
      sales: %{
        total: processed_data.sales.total,
        formatted: format_money(processed_data.sales.total)
      },
      costs: %{
        total: processed_data.costs.total,
        formatted: format_money(processed_data.costs.total)
      },
      goal: %{
        total: processed_data.goals.daily,
        formatted: format_money(processed_data.goals.daily),
        percentage: processed_data.percentages.goal_completion,
        formatted_percentage: format_percentage(processed_data.percentages.goal_completion)
      },
      profit: %{
        percentage: processed_data.percentages.profit_margin,
        formatted: format_percentage(processed_data.percentages.profit_margin)
      },
      stores: format_stores_data(processed_data.stores),
      nfs_count: processed_data.sales.invoices_count,
      last_update: DateTime.utc_now(),
      api_status: :ok
    }

    {:ok, formatted}
  end

  defp extract_sales_data(data) do
    %{
      total: get_numeric_value(data, "sale", 0.0),
      invoices_count: get_numeric_value(data, "nfs", 0) |> trunc()
    }
  end

  defp extract_costs_data(data) do
    %{
      total: get_numeric_value(data, "cost", 0.0),
      devolutions: get_numeric_value(data, "devolution", 0.0)
    }
  end

  defp extract_goals_data(data) do
    %{
      daily: get_numeric_value(data, "objetivo", 0.0)
    }
  end

  defp extract_stores_data(data) do
    case Map.get(data, "companies") do
      companies when is_list(companies) ->
        Enum.map(companies, &process_store_data/1)

      _ ->
        []
    end
  end

  defp process_store_data(store_data) do
    %{
      id: Map.get(store_data, "id"),
      name: Map.get(store_data, "nome", "Loja Sem Nome"),
      daily_sales: get_numeric_value(store_data, "venda_dia", 0.0),
      daily_goal: get_numeric_value(store_data, "meta_dia", 0.0),
      hourly_goal: get_numeric_value(store_data, "meta_hora", 0.0),
      invoices_count: get_numeric_value(store_data, "qtde_nfs", 0),
      hourly_percentage: get_numeric_value(store_data, "perc_hora", 0.0),
      daily_percentage: get_numeric_value(store_data, "perc_dia", 0.0),
      status: determine_store_status(store_data)
    }
  end

  defp calculate_percentages(data) do
    sale = get_numeric_value(data, "sale", 0.0)
    goal = get_numeric_value(data, "objetivo", 0.0)
    cost = get_numeric_value(data, "cost", 0.0)

    goal_completion = if goal > 0, do: sale / goal * 100, else: 0.0
    profit_margin = if sale > 0, do: (sale - cost) / sale * 100, else: 0.0

    %{
      goal_completion: goal_completion,
      profit_margin: profit_margin,
      yesterday_completion: get_numeric_value(data, "percentualSale", 0.0)
    }
  end

  defp determine_store_status(store_data) do
    perc_hora = get_numeric_value(store_data, "perc_hora", 0.0)
    venda_dia = get_numeric_value(store_data, "venda_dia", 0.0)

    cond do
      perc_hora >= 100 -> :goal_achieved
      venda_dia == 0 -> :no_sales
      perc_hora < 50 -> :below_target
      true -> :on_track
    end
  end

  defp format_stores_data(stores) do
    Enum.map(stores, fn store ->
      Map.merge(store, %{
        daily_sales_formatted: format_money(store.daily_sales),
        daily_goal_formatted: format_money(store.daily_goal),
        hourly_goal_formatted: format_money(store.hourly_goal),
        hourly_percentage_formatted: format_percentage(store.hourly_percentage),
        daily_percentage_formatted: format_percentage(store.daily_percentage)
      })
    end)
  end

  defp analyze_metrics_for_alerts(metrics) do
    alerts = []

    current_hour =
      DateTime.utc_now()
      |> DateTime.to_time()
      |> Time.to_seconds_after_midnight()
      |> Integer.floor_div(3600)

    alerts =
      if metrics.goal.percentage < 50 and current_hour > 14 do
        [
          create_alert(
            :warning,
            "Meta diária em risco - apenas #{metrics.goal.formatted_percentage} atingido"
          )
          | alerts
        ]
      else
        alerts
      end

    low_performance_stores = Enum.filter(metrics.stores, &(&1.hourly_percentage < 30))

    alerts =
      if length(low_performance_stores) > 0 do
        store_names = Enum.map_join(low_performance_stores, ", ", fn store -> store.name end)
        [create_alert(:info, "Lojas abaixo da meta: #{store_names}") | alerts]
      else
        alerts
      end

    alerts =
      if metrics.sales.total == 0 and current_hour > 9 do
        [create_alert(:error, "Nenhuma venda registrada hoje") | alerts]
      else
        alerts
      end

    alerts
  end

  defp create_alert(type, message) do
    %{
      id: System.unique_integer([:positive]),
      type: type,
      message: message,
      timestamp: DateTime.utc_now()
    }
  end

  defp goal_achieved?(store_metrics) do
    store_metrics.daily_percentage >= 100
  end

  defp trigger_celebration(store_metrics) do
    celebration_data = %{
      store_name: store_metrics.name,
      achieved: store_metrics.daily_sales,
      target: store_metrics.daily_goal,
      percentage: store_metrics.daily_percentage,
      timestamp: DateTime.utc_now(),
      celebration_id: System.unique_integer([:positive])
    }

    Phoenix.PubSub.broadcast(
      App.PubSub,
      "dashboard:goals",
      {:daily_goal_achieved, celebration_data}
    )

    :ok
  end

  defp validate_sale_data(sale_data) do
    required_fields = [:seller_name, :amount, :product]

    case Enum.all?(required_fields, &Map.has_key?(sale_data, &1)) do
      true -> {:ok, sale_data}
      false -> {:error, "Dados de venda incompletos"}
    end
  end

  defp save_sale(sale_data) do
    sale_type = Map.get(sale_data, :type, :api)

    if sale_type == :simulated do
      {:error, "Vendas simuladas não são mais permitidas"}
    else
      sale_attrs = %{
        seller_name: Map.get(sale_data, :seller_name, "Vendedor Desconhecido"),
        store: Map.get(sale_data, :store, "Loja Não Informada"),
        sale_value: Map.get(sale_data, :amount, Map.get(sale_data, :sale_value, 0.0)),
        objetivo: Map.get(sale_data, :objetivo, 0.0),
        timestamp: Map.get(sale_data, :timestamp, DateTime.utc_now()),
        type: sale_type,  # :api ou :sale_supervisor
        product: Map.get(sale_data, :product),
        category: Map.get(sale_data, :category),
        brand: Map.get(sale_data, :brand),
        status: Map.get(sale_data, :status, "completed"),
        celebration_id: Map.get(sale_data, :celebration_id)
      }

      case App.Sales.create_sale(sale_attrs) do
        {:ok, sale} -> {:ok, format_saved_sale(sale)}
        {:error, changeset} -> {:error, "Erro ao salvar venda: #{inspect(changeset.errors)}"}
      end
    end
  end

  defp format_saved_sale(sale) do
    %{
      id: sale.id,
      seller_name: sale.seller_name,
      store: sale.store,
      sale_value: Decimal.to_float(sale.sale_value),
      objetivo: Decimal.to_float(sale.objetivo || Decimal.new(0)),
      timestamp: sale.timestamp,
      type: sale.type,
      product: sale.product,
      category: sale.category,
      brand: sale.brand,
      status: sale.status,
      celebration_id: sale.celebration_id
    }
  end

  defp broadcast_sale(sale_data) do
    Phoenix.PubSub.broadcast(App.PubSub, "sales:feed", {:new_sale, sale_data})
    :ok
  end

  @doc """
  Exporta dados do dashboard em diferentes formatos.
  """
  def export_data(metrics, format) when format in ["csv", "json", "xlsx"] do
    case format do
      "csv" -> export_to_csv(metrics)
      "json" -> export_to_json(metrics)
      "xlsx" -> export_to_excel(metrics)
    end
  end

  def export_data(_metrics, format) do
    {:error, "Formato não suportado: #{format}"}
  end

  @doc """
  Processa dados brutos da API em métricas estruturadas.
  """
  def parse_api_data(raw_data) when is_map(raw_data) do
    try do
      with {:ok, processed_data} <- process_data(raw_data),
           {:ok, formatted_data} <- format_for_display(processed_data) do
        {:ok, formatted_data}
      else
        error -> {:error, "Erro no processamento: #{inspect(error)}"}
      end
    rescue
      error -> {:error, "Erro ao processar dados: #{inspect(error)}"}
    end
  end

  def parse_api_data(_), do: {:error, "Dados inválidos"}

  @doc """
  Retorna métricas padrão quando não há dados disponíveis.
  """
  def get_default_metrics do
    %{
      sales: %{total: 0.0, formatted: "R$ 0,00"},
      costs: %{total: 0.0, formatted: "R$ 0,00", devolutions: 0.0},
      goal: %{
        total: 0.0,
        formatted: "R$ 0,00",
        percentage: 0.0,
        formatted_percentage: "0,00%"
      },
      profit: %{percentage: 0.0, formatted: "0,00%"},
      stores: [],
      nfs_count: 0,
      last_update: DateTime.utc_now(),
      api_status: :no_data
    }
  end

  defp format_sale_for_feed(sale_data) do
    sale_value = normalize_decimal_value(sale_data.sale_value)
    objetivo = normalize_decimal_value(sale_data.objetivo)

    %{
      id: sale_data.id,
      seller_name: sale_data.seller_name,
      store: sale_data.store,
      sale_value: sale_value,
      sale_value_formatted: format_money(sale_value),
      objetivo: objetivo,
      objetivo_formatted: format_money(objetivo),
      timestamp: sale_data.timestamp,
      timestamp_formatted: format_datetime(sale_data.timestamp),
      type: sale_data.type
    }
  end

  defp format_and_save_api_sale(sale_data) do
    sale_value = normalize_decimal_value(sale_data.sale_value)
    objetivo = normalize_decimal_value(sale_data.objetivo)

    sale_attrs = %{
      seller_name: sale_data.seller_name,
      store: sale_data.store,
      sale_value: sale_value,
      objetivo: objetivo,
      timestamp: sale_data.timestamp,
      type: :api,
      product: nil,
      category: nil,
      brand: nil,
      status: "completed"
    }

    case App.Sales.create_sale(sale_attrs) do
      {:ok, saved_sale} ->
        %{
          id: saved_sale.id,
          seller_name: saved_sale.seller_name,
          store: saved_sale.store,
          sale_value: Decimal.to_float(saved_sale.sale_value),
          sale_value_formatted: format_money(Decimal.to_float(saved_sale.sale_value)),
          objetivo: Decimal.to_float(saved_sale.objetivo || Decimal.new(0)),
          objetivo_formatted: format_money(Decimal.to_float(saved_sale.objetivo || Decimal.new(0))),
          timestamp: saved_sale.timestamp,
          timestamp_formatted: format_datetime(saved_sale.timestamp),
          type: saved_sale.type
        }
      {:error, _reason} ->

        %{
          id: sale_data.id,
          seller_name: sale_data.seller_name,
          store: sale_data.store,
          sale_value: sale_value,
          sale_value_formatted: format_money(sale_value),
          objetivo: objetivo,
          objetivo_formatted: format_money(objetivo),
          timestamp: sale_data.timestamp,
          timestamp_formatted: format_datetime(sale_data.timestamp),
          type: :api
        }
    end
  end

  defp get_store_metrics(_store_id) do
    {:ok, %{}}
  end

  defp filter_stores(stores, []), do: stores

  defp filter_stores(stores, store_ids) do
    Enum.filter(stores, &(&1.id in store_ids))
  end

  defp calculate_store_performance(stores_data) do
    stores_data
  end

  defp get_numeric_value(data, key, default) when is_map(data) do
    case Map.get(data, key, default) do
      value when is_float(value) -> value
      value when is_integer(value) -> value * 1.0
      value when is_binary(value) -> parse_numeric_string(value, default)
      _ -> default
    end
  end

  defp parse_numeric_string(str, default) do
    case Float.parse(str) do
      {num, _} -> num
      :error -> default
    end
  end

  @doc """
  Formata valores monetários para o padrão brasileiro com separador de milhares.

  ## Examples

      iex> Dashboard.format_money(1500.0)
      "R$ 1.500,00"

      iex> Dashboard.format_money(1234567.89)
      "R$ 1.234.567,89"

      iex> Dashboard.format_money(nil)
      "R$ 0,00"
  """
  def format_money(amount) when is_float(amount) do
    "R$ " <>
      (amount
       |> :erlang.float_to_binary(decimals: 2)
       |> String.replace(".", ",")
       |> add_thousands_separator())
  end

  def format_money(amount) when is_integer(amount) do
    format_money(amount * 1.0)
  end

  def format_money(_), do: "R$ 0,00"

  defp add_thousands_separator(str) do
    [int, frac] = String.split(str, ",")

    int_formatted =
      int
      |> String.reverse()
      |> String.replace(~r/(...)(?=.)/, "\\1.")
      |> String.reverse()

    int_formatted <> "," <> frac
  end

  defp format_percentage(percentage) when is_float(percentage) do
    percentage
    |> :erlang.float_to_binary(decimals: 2)
    |> String.replace(".", ",")
    |> Kernel.<>("%")
  end

  defp format_percentage(percentage) when is_integer(percentage) do
    format_percentage(percentage * 1.0)
  end

  defp format_percentage(_), do: "0,00%"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%d/%m/%Y %H:%M")
  end

  defp export_to_csv(metrics) do
    headers = ["Loja", "Meta Diária", "Vendas", "Percentual", "Status"]

    rows =
      Enum.map(metrics.stores, fn store ->
        [
          store.name,
          store.daily_goal_formatted,
          store.daily_sales_formatted,
          store.daily_percentage_formatted,
          format_status(store.status)
        ]
      end)

    csv_content =
      [headers | rows]
      |> Enum.map_join("\n", &Enum.join(&1, ","))

    {:ok, csv_content}
  end

  defp export_to_json(metrics) do
    export_data = %{
      summary: %{
        total_sales: metrics.sales.formatted,
        total_goal: metrics.goal.formatted,
        completion_percentage: metrics.goal.formatted_percentage,
        export_timestamp: DateTime.utc_now()
      },
      stores: metrics.stores
    }

    case Jason.encode(export_data, pretty: true) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, "Erro na codificação JSON: #{inspect(reason)}"}
    end
  end

  defp export_to_excel(_metrics) do
    {:error, "Exportação para Excel não implementada ainda"}
  end

  defp format_status(status) do
    case status do
      :goal_achieved -> "Meta Atingida"
      :on_track -> "No Caminho"
      :below_target -> "Abaixo da Meta"
      :no_sales -> "Sem Vendas"
      _ -> "Desconhecido"
    end
  end

  defp normalize_decimal_value(value) when is_float(value), do: Float.round(value, 2)
  defp normalize_decimal_value(value) when is_integer(value), do: Float.round(value * 1.0, 2)

  defp normalize_decimal_value(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> Float.round(num, 2)
      :error -> 0.0
    end
  end

  defp normalize_decimal_value(nil), do: 0.0
  defp normalize_decimal_value(_), do: 0.0
end
