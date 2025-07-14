defmodule App.Sales do
  @moduledoc """
  Contexto para gerenciar vendas individuais do sistema.

  Fornece funções para criar, buscar e listar vendas vindas da API externa.
  Inclui funcionalidades para cálculo de métricas e geração de feeds de vendas.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Schemas.Sale

  @spec create_sale(map()) :: {:ok, Sale.t()} | {:error, Ecto.Changeset.t()}
  def create_sale(attrs) do
    attrs_with_timestamp = Map.put_new(attrs, :timestamp, DateTime.utc_now())

    %Sale{}
    |> Sale.changeset(attrs_with_timestamp)
    |> Repo.insert()
  end

  @spec list_sales(keyword()) :: [Sale.t()]
  def list_sales(opts \\ []) do
    limit = Keyword.get(opts, :limit, 15)
    offset = Keyword.get(opts, :offset, 0)
    date_from = Keyword.get(opts, :date_from)
    date_to = Keyword.get(opts, :date_to)
    type = Keyword.get(opts, :type)
    store = Keyword.get(opts, :store)
    seller_name = Keyword.get(opts, :seller_name)

    Sale
    |> maybe_filter_by_date_range(date_from, date_to)
    |> maybe_filter_by_type(type)
    |> maybe_filter_by_store(store)
    |> maybe_filter_by_seller(seller_name)
    |> order_by(desc: :timestamp)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @spec get_sales_feed(integer()) :: {:ok, [map()]} | {:error, term()}
  def get_sales_feed(limit \\ 50) do
    try do
      sales =
        Sale
        |> where([s], s.timestamp >= ago(1, "day"))
        |> order_by(desc: :timestamp)
        |> limit(^limit)
        |> Repo.all()
        |> Enum.map(&format_sale_for_feed/1)

      {:ok, sales}
    rescue
      error -> {:error, error}
    end
  end

  @spec get_sale(integer()) :: Sale.t() | nil
  def get_sale(id) do
    Repo.get(Sale, id)
  end

  @spec calculate_sales_metrics(keyword()) :: map()
  def calculate_sales_metrics(opts \\ []) do
    date_from = Keyword.get(opts, :date_from, Date.utc_today())
    date_to = Keyword.get(opts, :date_to, Date.utc_today())

    query =
      from s in Sale,
      where: fragment("DATE(?)", s.timestamp) >= ^date_from,
      where: fragment("DATE(?)", s.timestamp) <= ^date_to,
      select: %{
        total_sales: sum(s.sale_value),
        total_objetivo: sum(s.objetivo),
        count: count(s.id),
        avg_sale: avg(s.sale_value)
      }

    case Repo.one(query) do
      nil -> %{total_sales: 0.0, total_objetivo: 0.0, count: 0, avg_sale: 0.0}
      metrics ->
        %{
          total_sales: Decimal.to_float(metrics.total_sales || Decimal.new(0)),
          total_objetivo: Decimal.to_float(metrics.total_objetivo || Decimal.new(0)),
          count: metrics.count || 0,
          avg_sale: metrics.avg_sale || 0.0
        }
    end
  end

  @spec cleanup_old_sales() :: {integer(), nil}
  def cleanup_old_sales do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-30, :day)

    from(s in Sale, where: s.timestamp < ^cutoff_date)
    |> Repo.delete_all()
  end

  def list_daily_sales_history(limit \\ 30) do
    import Ecto.Query
    alias App.Schemas.DailySalesHistory

    DailySalesHistory
    |> order_by([h], desc: h.date)
    |> limit(^limit)
    |> select([h], %{date: h.date, total_sales: h.total_sales})
    |> App.Repo.all()
    |> Enum.reverse() # do mais antigo para o mais recente
  end

  @doc """
  Retorna o faturamento total por hora para um determinado dia.
  O resultado é uma lista de mapas: [%{hour: 0..23, total_sales: float}]
  """
  def list_hourly_sales_history(date \\ Date.utc_today()) do
    import Ecto.Query
    from(s in Sale,
      where: fragment("DATE(?)", s.timestamp) == ^date,
      group_by: fragment("EXTRACT(HOUR FROM ?)", s.timestamp),
      select: %{
        hour: fragment("EXTRACT(HOUR FROM ?)", s.timestamp),
        total_sales: sum(s.sale_value)
      }
    )
    |> Repo.all()
    |> Enum.map(fn %{hour: hour, total_sales: total_sales} ->
      %{hour: trunc(hour), total_sales: Decimal.to_float(total_sales || Decimal.new(0))}
    end)
  end


  defp maybe_filter_by_date_range(query, nil, nil), do: query
  defp maybe_filter_by_date_range(query, date_from, nil) do
    where(query, [s], fragment("DATE(?)", s.timestamp) >= ^date_from)
  end
  defp maybe_filter_by_date_range(query, nil, date_to) do
    where(query, [s], fragment("DATE(?)", s.timestamp) <= ^date_to)
  end
  defp maybe_filter_by_date_range(query, date_from, date_to) do
    where(query, [s],
      fragment("DATE(?)", s.timestamp) >= ^date_from and
      fragment("DATE(?)", s.timestamp) <= ^date_to
    )
  end

  defp maybe_filter_by_type(query, nil), do: query
  defp maybe_filter_by_type(query, type) do
    where(query, [s], s.type == ^type)
  end

  defp maybe_filter_by_store(query, nil), do: query
  defp maybe_filter_by_store(query, store) do
    where(query, [s], ilike(s.store, ^"%#{store}%"))
  end

  defp maybe_filter_by_seller(query, nil), do: query
  defp maybe_filter_by_seller(query, seller_name) do
    where(query, [s], ilike(s.seller_name, ^"%#{seller_name}%"))
  end

  defp format_sale_for_feed(sale) do
    %{
      id: sale.id,
      seller_name: sale.seller_name,
      store: sale.store,
      sale_value: Decimal.to_float(sale.sale_value),
      sale_value_formatted: App.Dashboard.format_money(Decimal.to_float(sale.sale_value)),
      objetivo: Decimal.to_float(sale.objetivo || Decimal.new(0)),
      objetivo_formatted: App.Dashboard.format_money(Decimal.to_float(sale.objetivo || Decimal.new(0))),
      timestamp: sale.timestamp,
      timestamp_formatted: format_datetime(sale.timestamp),
      type: sale.type,
      product: sale.product,
      category: sale.category,
      brand: sale.brand,
      status: sale.status
    }
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end
end
