defmodule App.Tags do
  @moduledoc """
  Módulo responsável por gerenciar tags de pedidos.
  """

  import Ecto.Query
  alias App.Repo
  alias App.Tags.{Tag, OrderTag}

  @doc """
  Lista todas as tags ativas.
  """
  def list_tags(store_id \\ nil) do
    query = from t in Tag, where: t.is_active == true

    query = if store_id do
      from t in query, where: t.store_id == ^store_id
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Busca uma tag por ID.
  """
  def get_tag!(id), do: Repo.get!(Tag, id)

  @doc """
  Cria uma nova tag.
  """
  def create_tag(attrs \\ %{}) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Atualiza uma tag.
  """
  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deleta uma tag (soft delete).
  """
  def delete_tag(%Tag{} = tag) do
    tag
    |> Tag.changeset(%{is_active: false})
    |> Repo.update()
  end

  @doc """
  Adiciona uma tag a um pedido.
  """
  def add_tag_to_order(order_id, tag_id, user_id) do
    %OrderTag{}
    |> OrderTag.changeset(%{
      order_id: order_id,
      tag_id: tag_id,
      added_by: user_id,
      added_at: App.DateTimeHelper.now()
    })
    |> Repo.insert()
  end

  @doc """
  Remove uma tag de um pedido.
  """
  def remove_tag_from_order(order_id, tag_id) do
    from(ot in OrderTag, where: ot.order_id == ^order_id and ot.tag_id == ^tag_id)
    |> Repo.delete_all()
  end

  @doc """
  Lista todas as tags de um pedido.
  """
  def get_order_tags(order_id) do
    from(ot in OrderTag,
      join: t in Tag, on: ot.tag_id == t.id,
      where: ot.order_id == ^order_id and t.is_active == true,
      select: %{
        id: t.id,
        name: t.name,
        color: t.color,
        description: t.description,
        added_at: ot.added_at,
        added_by: ot.added_by
      }
    )
    |> Repo.all()
  end

  @doc """
  Lista todos os pedidos com uma tag específica.
  """
  def get_orders_with_tag(tag_id) do
    from(ot in OrderTag,
      where: ot.tag_id == ^tag_id,
      select: ot.order_id
    )
    |> Repo.all()
  end

  @doc """
  Busca tags por nome (para autocomplete).
  """
  def search_tags(search_query, store_id \\ nil) do
    query = from t in Tag,
      where: t.is_active == true and ilike(t.name, ^"%#{search_query}%")

    query = if store_id do
      from t in query, where: t.store_id == ^store_id
    else
      query
    end

    query
    |> limit(10)
    |> Repo.all()
  end

  @doc """
  Cria tags padrão para uma loja.
  """
  def create_default_tags(store_id, created_by) do
    default_tags = [
      %{name: "Urgente", color: "#ef4444", description: "Pedidos que precisam de atenção imediata"},
      %{name: "Pendente", color: "#f59e0b", description: "Pedidos aguardando resposta"},
      %{name: "Resolvido", color: "#10b981", description: "Pedidos com problema resolvido"},
      %{name: "Cancelado", color: "#6b7280", description: "Pedidos cancelados"},
      %{name: "Em Análise", color: "#3b82f6", description: "Pedidos sendo analisados"},
      %{name: "Aprovado", color: "#8b5cf6", description: "Pedidos aprovados"},
      %{name: "Rejeitado", color: "#dc2626", description: "Pedidos rejeitados"},
      %{name: "Vip", color: "#fbbf24", description: "Clientes VIP"}
    ]

    Enum.each(default_tags, fn tag_attrs ->
      create_tag(Map.merge(tag_attrs, %{
        store_id: store_id,
        created_by: created_by
      }))
    end)
  end

  @doc """
  Conta quantos pedidos têm cada tag.
  """
  def get_tag_statistics(store_id \\ nil) do
    base_query = from t in Tag, where: t.is_active == true

    query = if store_id do
      from t in base_query, where: t.store_id == ^store_id
    else
      base_query
    end

    from(t in query,
      left_join: ot in OrderTag, on: t.id == ot.tag_id,
      group_by: [t.id, t.name, t.color],
      select: %{id: t.id, name: t.name, color: t.color, count: count(ot.order_id)}
    )
    |> Repo.all()
  end
end
