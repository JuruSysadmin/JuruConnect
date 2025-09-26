defmodule App.Tags do
  @moduledoc """
  Módulo responsável por gerenciar tags de tratativas.
  """

  import Ecto.Query
  alias App.Repo
  alias App.Tags.{Tag, TreatyTag}

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
  Adiciona uma tag a uma tratativa.
  """
  def add_tag_to_treaty(treaty_id, tag_id, user_id) do
    %TreatyTag{}
    |> TreatyTag.changeset(%{
      treaty_id: treaty_id,
      tag_id: tag_id,
      added_by: user_id,
      added_at: App.DateTimeHelper.now()
    })
    |> Repo.insert()
  end

  @doc """
  Remove uma tag de uma tratativa.
  """
  def remove_tag_from_treaty(treaty_id, tag_id) do
    from(tt in TreatyTag, where: tt.treaty_id == ^treaty_id and tt.tag_id == ^tag_id)
    |> Repo.delete_all()
  end

  @doc """
  Lista todas as tags de uma tratativa.
  """
  def get_treaty_tags(treaty_id) do
    from(tt in TreatyTag,
      join: t in Tag, on: tt.tag_id == t.id,
      where: tt.treaty_id == ^treaty_id and t.is_active == true,
      select: %{
        id: t.id,
        name: t.name,
        color: t.color,
        description: t.description,
        added_at: tt.added_at,
        added_by: tt.added_by
      }
    )
    |> Repo.all()
  end

  @doc """
  Lista todas as tratativas com uma tag específica.
  """
  def get_treaties_with_tag(tag_id) do
    from(tt in TreatyTag,
      where: tt.tag_id == ^tag_id,
      select: tt.treaty_id
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
      %{name: "EM ANÁLISE", color: "#3b82f6", description: "Tratativa sendo analisada pela equipe"},
      %{name: "AGUARDANDO RESPOSTA", color: "#f59e0b", description: "Aguardando resposta do cliente"},
      %{name: "RESOLVIDO", color: "#10b981", description: "Problema resolvido com sucesso"},
      %{name: "URGENTE", color: "#ef4444", description: "Tratativas que precisam de atenção imediata"},
      %{name: "PENDENTE", color: "#f59e0b", description: "Tratativas aguardando resposta"},
      %{name: "CANCELADO", color: "#6b7280", description: "Tratativas canceladas"},
      %{name: "APROVADO", color: "#8b5cf6", description: "Tratativas aprovadas"},
      %{name: "REJEITADO", color: "#dc2626", description: "Tratativas rejeitadas"},
      %{name: "VIP", color: "#fbbf24", description: "Clientes VIP"},
      %{name: "EM PROCESSO", color: "#06b6d4", description: "Tratativa em processo de resolução"},
      %{name: "FINALIZADO", color: "#059669", description: "Tratativa finalizada com sucesso"},
      %{name: "REABERTO", color: "#dc2626", description: "Tratativa reaberta pelo cliente"}
    ]

    Enum.each(default_tags, fn tag_attrs ->
      create_tag(Map.merge(tag_attrs, %{
        store_id: store_id,
        created_by: created_by
      }))
    end)
  end

  @doc """
  Conta quantas tratativas têm cada tag.
  """
  def get_tag_statistics(store_id \\ nil) do
    base_query = from t in Tag, where: t.is_active == true

    query = if store_id do
      from t in base_query, where: t.store_id == ^store_id
    else
      base_query
    end

    from(t in query,
      left_join: tt in TreatyTag, on: t.id == tt.tag_id,
      group_by: [t.id, t.name, t.color],
      select: %{id: t.id, name: t.name, color: t.color, count: count(tt.treaty_id)}
    )
    |> Repo.all()
  end
end
