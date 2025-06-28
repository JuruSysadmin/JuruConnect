defmodule App.CelebrationManager do
  @moduledoc """
  Gerenciador de celebrações baseado em dados reais da API.

  Detecta automaticamente quando metas são atingidas e dispara
  celebrações adequadas baseadas no tipo e magnitude da conquista.

  Inclui sistema de cache para evitar celebrações duplicadas.
  """

  use GenServer
  require Logger
  alias App.DashboardDataServer

  # Cache de celebrações por 1 hora
  @cache_ttl_ms 3_600_000

  @celebration_types %{
    daily_goal: %{
      threshold: 100.0,
      message: "Meta Diária Atingida!",
      level: :standard,
      sound: "goal_achieved.mp3"
    },
    hourly_goal: %{
      threshold: 100.0,
      message: "Meta Horária Conquistada!",
      level: :minor,
      sound: "hourly_goal.mp3"
    },
    exceptional_performance: %{
      threshold: 120.0,
      message: "Performance Excepcional!",
      level: :epic,
      sound: "epic_achievement.mp3"
    },
    monthly_milestone: %{
      threshold: 100.0,
      message: "Marco Mensal Alcançado!",
      level: :major,
      sound: "monthly_goal.mp3"
    },
    top_seller: %{
      threshold: 150.0,
      message: "Vendedor Destaque!",
      level: :legendary,
      sound: "top_seller.mp3"
    }
  }

  ## GenServer API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    # Limpa cache periodicamente
    schedule_cache_cleanup()
    {:ok, %{celebrations_cache: %{}}}
  end

  @impl true
  def handle_info(:cleanup_cache, state) do
    current_time = System.monotonic_time(:millisecond)

    cleaned_cache =
      state.celebrations_cache
      |> Enum.filter(fn {_key, timestamp} ->
        current_time - timestamp < @cache_ttl_ms
      end)
      |> Enum.into(%{})

    Logger.debug("Cache limpo: #{map_size(state.celebrations_cache)} -> #{map_size(cleaned_cache)} entradas")

    schedule_cache_cleanup()
    {:noreply, %{state | celebrations_cache: cleaned_cache}}
  end

  @impl true
  def handle_call({:check_celebration_cache, cache_key}, _from, state) do
    current_time = System.monotonic_time(:millisecond)

    case Map.get(state.celebrations_cache, cache_key) do
      nil ->
        # Não existe no cache, adiciona
        new_cache = Map.put(state.celebrations_cache, cache_key, current_time)
        {:reply, :not_found, %{state | celebrations_cache: new_cache}}

      cached_time when current_time - cached_time < @cache_ttl_ms ->
        # Existe e ainda é válido
        {:reply, :found, state}

      _expired_time ->
        # Existe mas expirou, atualiza
        new_cache = Map.put(state.celebrations_cache, cache_key, current_time)
        {:reply, :not_found, %{state | celebrations_cache: new_cache}}
    end
  end

  ## Public API

  @doc """
  Processa dados recebidos da API e verifica celebrações.
  Inclui cache para evitar duplicatas.
  """
  def process_api_data(api_data) when is_map(api_data) do
    celebrations = []

        celebrations =
      celebrations
      |> check_company_goals(Map.get(api_data, "companies", []))
      # Outros tipos desabilitados - apenas meta diária quando venda > meta
      # |> check_individual_sellers(Map.get(api_data, "companies", []))
      # |> check_monthly_goals(api_data)
      # |> check_system_wide_metrics(api_data)

    # Filtra celebrações já enviadas
    filtered_celebrations =
      celebrations
      |> Enum.filter(&should_send_celebration?/1)

        # Broadcast apenas celebrações novas
    Enum.each(filtered_celebrations, &broadcast_celebration/1)

    companies_count = length(Map.get(api_data, "companies", []))

    if length(filtered_celebrations) > 0 do
      Logger.info("Verificadas #{companies_count} lojas → #{length(filtered_celebrations)} metas diárias atingidas")
    else
      Logger.debug("Verificadas #{companies_count} lojas → Nenhuma meta diária atingida ainda")
    end

    {:ok, filtered_celebrations}
  end

  def process_api_data(_), do: {:ok, []}

  @doc """
  Processa nova venda e verifica se gera celebração.
  """
    def process_new_sale(sale_data, current_totals) do
    # Celebrações de vendas individuais desabilitadas - apenas meta diária
    celebrations = []

    # Verificações desabilitadas conforme solicitado
    # celebrations = check_individual_sale_celebration(sale_data, celebrations)
    # celebrations = check_milestone_celebrations(current_totals, celebrations)

    # Nenhuma celebração para vendas individuais
    {:ok, []}
  end

  # Funções privadas

  defp schedule_cache_cleanup do
    # Limpa cache a cada 10 minutos
    Process.send_after(self(), :cleanup_cache, 600_000)
  end

  defp should_send_celebration?(celebration) do
    cache_key = create_cache_key(celebration)

    case GenServer.call(__MODULE__, {:check_celebration_cache, cache_key}) do
      :not_found -> true   # Nova celebração
      :found -> false      # Já foi enviada
    end
  rescue
    _error -> true  # Se há erro no cache, permite a celebração
  end

    defp create_cache_key(celebration) do
    today = Date.utc_today() |> Date.to_string()

    celebration.type
    |> create_cache_key_for_type(celebration, today)
  end

  # Funções específicas para cada tipo de celebração
  defp create_cache_key_for_type(:daily_goal, celebration, today) do
    store_name = get_cache_store_name(celebration)
    "daily_goal:#{store_name}:#{today}"
  end

  defp create_cache_key_for_type(:hourly_goal, celebration, today) do
    store_name = get_cache_store_name(celebration)
    hour = DateTime.utc_now().hour
    "hourly_goal:#{store_name}:#{today}:#{hour}"
  end

  defp create_cache_key_for_type(:exceptional_performance, celebration, today) do
    store_name = get_cache_store_name(celebration)
    percentage = celebration.percentage
    "exceptional_performance:#{store_name}:#{percentage}:#{today}"
  end

  defp create_cache_key_for_type(:top_seller, celebration, today) do
    seller_name = get_in(celebration.data, [:seller_name]) || "unknown"
    percentage = celebration.percentage
    "top_seller:#{seller_name}:#{percentage}:#{today}"
  end

  defp create_cache_key_for_type(:monthly_milestone, celebration, _today) do
    percentage = celebration.percentage
    month = Date.utc_today() |> Date.beginning_of_month() |> Date.to_string()
    "monthly_milestone:#{percentage}:#{month}"
  end

  defp create_cache_key_for_type(:exceptional_individual_sale, celebration, today) do
    seller_name = get_in(celebration.data, [:seller_name]) || "unknown"
    achieved = get_in(celebration.data, [:achieved]) || 0
    "exceptional_individual_sale:#{seller_name}:#{achieved}:#{today}"
  end

  defp create_cache_key_for_type(:sales_milestone, celebration, today) do
    total_sales = get_in(celebration.data, [:total_sales]) || 0
    milestone = trunc(total_sales / 10_000) * 10_000
    "sales_milestone:#{milestone}:#{today}"
  end

  defp create_cache_key_for_type(:nfs_milestone, celebration, today) do
    nfs_count = get_in(celebration.data, [:nfs_count]) || 0
    "nfs_milestone:#{nfs_count}:#{today}"
  end

  defp create_cache_key_for_type(type, celebration, today) do
    # Fallback genérico
    "#{type}:#{celebration.percentage}:#{today}"
  end

  defp get_cache_store_name(celebration) do
    get_in(celebration.data, [:store_name]) || "unknown"
  end

  defp check_company_goals(celebrations, companies) when is_list(companies) do
    new_celebrations =
      companies
      |> Enum.filter(&is_map/1)
      |> Enum.flat_map(&check_single_company_goals/1)

    celebrations ++ new_celebrations
  end

  defp check_company_goals(celebrations, _), do: celebrations

    defp check_single_company_goals(company) do
    celebrations = []

    # APENAS Meta diária quando venda > meta
    celebrations = check_daily_goal(company, celebrations)

    # Outros tipos desabilitados conforme solicitado
    # celebrations = check_hourly_goal(company, celebrations)
    # celebrations = check_exceptional_performance(company, celebrations)

    celebrations
  end

  defp check_daily_goal(company, celebrations) do
    venda_dia = get_numeric_value(company, :venda_dia, 0.0)
    meta_dia = get_numeric_value(company, :meta_dia, 0.0)

    # APENAS celebra quando venda > meta (valores absolutos)
    if meta_dia > 0 and venda_dia > meta_dia do
      perc_dia = (venda_dia / meta_dia * 100.0)

      celebration = create_celebration(
        :daily_goal,
        company,
        perc_dia,
        %{
          achieved: venda_dia,
          target: meta_dia,
          store_name: Map.get(company, :nome, "Loja Desconhecida")
        }
      )

      [celebration | celebrations]
    else
      celebrations
    end
  end

  defp check_hourly_goal(company, celebrations) do
    perc_hora = get_numeric_value(company, :perc_hora, 0.0)

    if perc_hora >= @celebration_types.hourly_goal.threshold do
      celebration = create_celebration(
        :hourly_goal,
        company,
        perc_hora,
        %{
          achieved: get_numeric_value(company, :venda_dia, 0.0),
          hourly_target: get_numeric_value(company, :meta_hora, 0.0),
          store_name: Map.get(company, :nome, "Loja Desconhecida")
        }
      )

      [celebration | celebrations]
    else
      celebrations
    end
  end

  defp check_exceptional_performance(company, celebrations) do
    perc_dia = get_numeric_value(company, :perc_dia, 0.0)

    if perc_dia >= @celebration_types.exceptional_performance.threshold do
      celebration = create_celebration(
        :exceptional_performance,
        company,
        perc_dia,
        %{
          achieved: get_numeric_value(company, :venda_dia, 0.0),
          target: get_numeric_value(company, :meta_dia, 0.0),
          store_name: Map.get(company, :nome, "Loja Desconhecida"),
          performance_level: get_performance_level(perc_dia)
        }
      )

      [celebration | celebrations]
    else
      celebrations
    end
  end

  defp check_individual_sellers(celebrations, companies) when is_list(companies) do
    # Extrai dados de vendedores de todas as lojas
    all_sellers =
      companies
      |> Enum.flat_map(fn company ->
        case Map.get(company, "saleSupervisor") do
          sellers when is_list(sellers) -> sellers
          _ -> []
        end
      end)

    # Verifica vendedores top
    new_celebrations =
      all_sellers
      |> Enum.filter(&is_top_seller/1)
      |> Enum.map(&create_seller_celebration/1)

    celebrations ++ new_celebrations
  end

  defp check_individual_sellers(celebrations, _), do: celebrations

  defp is_top_seller(seller) do
    percentual_objective = get_numeric_value(seller, "percentualObjective", 0.0)
    percentual_objective >= @celebration_types.top_seller.threshold
  end

  defp create_seller_celebration(seller) do
    percentual = get_numeric_value(seller, "percentualObjective", 0.0)

    create_celebration(
      :top_seller,
      seller,
      percentual,
      %{
        seller_name: Map.get(seller, "sellerName", "Vendedor Desconhecido"),
        store: Map.get(seller, "store", "Loja Desconhecida"),
        achieved: get_numeric_value(seller, "saleValue", 0.0),
        target: get_numeric_value(seller, "objetivo", 0.0),
        performance_level: get_performance_level(percentual)
      }
    )
  end

  defp check_monthly_goals(celebrations, api_data) do
    percentual_sale = get_numeric_value(api_data, "percentualSale", 0.0)

    if percentual_sale >= @celebration_types.monthly_milestone.threshold do
      celebration = create_celebration(
        :monthly_milestone,
        api_data,
        percentual_sale,
        %{
          achieved: get_numeric_value(api_data, "sale", 0.0),
          target: get_numeric_value(api_data, "objetive", 0.0),
          type: :system_wide
        }
      )

      [celebration | celebrations]
    else
      celebrations
    end
  end

  defp check_system_wide_metrics(celebrations, api_data) do
    # Verifica métricas gerais do sistema
    # Exemplo: Se o NFS do dia ultrapassou um marco
    nfs_today = get_numeric_value(api_data, "nfsToday", 0)

    if nfs_today > 0 and rem(nfs_today, 100) == 0 do
      celebration = %{
        type: :nfs_milestone,
        percentage: 100.0,
        data: %{
          nfs_count: nfs_today,
          message: "Marco de #{nfs_today} vendas hoje!"
        },
        timestamp: DateTime.utc_now(),
        celebration_id: System.unique_integer([:positive]),
        level: :minor
      }

      [celebration | celebrations]
    else
      celebrations
    end
  end

  defp check_individual_sale_celebration(sale_data, celebrations) do
    sale_value = Map.get(sale_data, :sale_value, 0.0)
    objetivo = Map.get(sale_data, :objetivo, 0.0)

    # Celebra vendas individuais excepcionais
    if objetivo > 0 and sale_value >= objetivo * 2.0 do
      # Garante que o cálculo seja em float
      safe_percentage = (ensure_float(sale_value) / ensure_float(objetivo) * 100.0)

      celebration = %{
        type: :exceptional_individual_sale,
        percentage: Float.round(safe_percentage, 1),
        data: %{
          seller_name: Map.get(sale_data, :seller_name, "Vendedor"),
          store: Map.get(sale_data, :store, "Loja"),
          achieved: sale_value,
          target: objetivo,
          message: "Venda Excepcional!"
        },
        timestamp: DateTime.utc_now(),
        celebration_id: System.unique_integer([:positive]),
        level: :epic
      }

      [celebration | celebrations]
    else
      celebrations
    end
  end

  defp check_milestone_celebrations(current_totals, celebrations) do
    # Verifica marcos importantes nos totais
    total_sales = Map.get(current_totals, :sale_num, 0.0)

    # Celebra marcos de valor (múltiplos de 10.000)
    if total_sales > 0 and rem(trunc(total_sales), 10_000) == 0 do
      celebration = %{
        type: :sales_milestone,
        percentage: 100.0,
        data: %{
          total_sales: total_sales,
          message: "Marco de R$ #{trunc(total_sales)} em vendas!"
        },
        timestamp: DateTime.utc_now(),
        celebration_id: System.unique_integer([:positive]),
        level: :major
      }

      [celebration | celebrations]
    else
      celebrations
    end
  end

  defp create_celebration(type, data, percentage, extra_data) do
    celebration_config = Map.get(@celebration_types, type)

    # Garante que percentage seja um float antes de fazer round
    safe_percentage =
      case percentage do
        p when is_float(p) -> p
        p when is_integer(p) -> p * 1.0
        p when is_binary(p) ->
          case Float.parse(p) do
            {num, _} -> num
            :error -> 0.0
          end
        _ -> 0.0
      end

    %{
      type: type,
      percentage: Float.round(safe_percentage, 1),
      data: Map.merge(%{
        message: celebration_config.message,
        sound: celebration_config.sound
      }, extra_data),
      timestamp: DateTime.utc_now(),
      celebration_id: System.unique_integer([:positive]),
      level: celebration_config.level
    }
  end

  defp get_performance_level(percentage) when percentage >= 200.0, do: :legendary
  defp get_performance_level(percentage) when percentage >= 150.0, do: :epic
  defp get_performance_level(percentage) when percentage >= 120.0, do: :excellent
  defp get_performance_level(_), do: :good

  defp broadcast_celebration(celebration) do
    case celebration.type do
      :daily_goal ->
        store_name = get_in(celebration.data, [:store_name])
        achieved = get_in(celebration.data, [:achieved])
        target = get_in(celebration.data, [:target])

        Logger.info("META DIÁRIA ATINGIDA! #{store_name} - Vendeu: R$ #{:erlang.float_to_binary(achieved, decimals: 2)} | Meta: R$ #{:erlang.float_to_binary(target, decimals: 2)} (#{celebration.percentage}%)")

      _ ->
        Logger.info("Celebração enviada: #{celebration.type} (#{celebration.percentage}%)")
    end

    Phoenix.PubSub.broadcast(
      App.PubSub,
      "dashboard:goals",
      {:goal_achieved_real, celebration}
    )
  end

  defp get_numeric_value(data, key, default) when is_map(data) do
    case Map.get(data, key) do
      value when is_float(value) -> value
      value when is_integer(value) -> value * 1.0  # Converte para float
      value when is_binary(value) ->
        case Float.parse(value) do
          {num, _} -> num
          :error -> ensure_float(default)
        end
      _ -> ensure_float(default)
    end
  end

  defp get_numeric_value(data, key, default) when is_atom(key) do
    get_numeric_value(data, Atom.to_string(key), default)
  end

  defp get_numeric_value(_, _, default), do: ensure_float(default)

  # Garante que o valor seja um float
  defp ensure_float(value) when is_float(value), do: value
  defp ensure_float(value) when is_integer(value), do: value * 1.0
  defp ensure_float(_), do: 0.0
end
