defmodule App.TreatyComments do
  @moduledoc """
  O módulo TreatyComments oferece funcionalidades CRUD para comentários internos e públicos
  relacionados às tratativas, permitindo que usuários adicionem notas e observações
  sobre o progresso das tratativas.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.TreatyComments.TreatyComment

  @doc """
  Cria um novo comentário para uma tratativa específica.

  ## Exemplos

      iex> create_comment(%{field: value})
      {:ok, %TreatyComment{}}

      iex> create_comment(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_comment(attrs \\ %{}) do
    %TreatyComment{}
    |> TreatyComment.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Retorna a lista de comentários relacionados a uma tratativa específica.
  """
  def get_treaty_comments(treaty_id) do
    from(c in TreatyComment,
      where: c.treaty_id == ^treaty_id and c.status == "active",
      order_by: [desc: c.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Retorna comentários filtrados por tipo específico.

  ## Types

  - `:internal` - Comentários internos (padrão)
  - `:public` - Comentários públicos

  """
  def get_treaty_comments(treaty_id, :internal) do
    from(c in TreatyComment,
      where: c.treaty_id == ^treaty_id and c.status == "active" and c.comment_type == "internal_note",
      order_by: [desc: c.inserted_at]
    )
    |> Repo.all()
  end

  def get_treaty_comments(treaty_id, :public) do
    from(c in TreatyComment,
      where: c.treaty_id == ^treaty_id and c.status == "active" and c.comment_type == "public_note",
      order_by: [desc: c.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Atualiza os dados de um comentário específico.

  ## Exemplos

      iex> update_comment(comment, %{field: new_value})
      {:ok, %TreatyComment{}}

      iex> update_comment(comment, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_comment(id, attrs) do
    comment = Repo.get(TreatyComment, id)

    if comment && comment.status == "active" do
      comment
      |> TreatyComment.update_changeset(attrs)
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Remove um comentário específico através de soft deletion.

  ## Exemplos

      iex> delete_comment(comment)
      {:ok, %TreatyComment{}}

      iex> delete_comment(bad_id)
      {:error, :not_found}

  """
  def delete_comment(id) do
    comment = Repo.get(TreatyComment, id)

    if comment && comment.status == "active" do
      comment
      |> TreatyComment.delete_changeset()
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Calcula estatísticas completas dos comentários de uma tratativa.

  Retorna um mapa com as seguintes informações:
  - `total_comments`: Total de comentários (incluindo deletados)
  - `active_comments`: Comentários ativos
  - `deleted_comments`: Comentários deletados (soft deletion)
  - `internal_comments`: Comentários internos
  - `public_comments`: Comentários públicos
  - `comments_by_user`: Contagem de comentários por usuário

  ## Exemplos

      iex> get_comment_stats(treaty_id)
      %{
        total_comments: 10,
        active_comments: 8,
        deleted_comments: 2,
        internal_comments: 5,
        public_comments: 3,
        comments_by_user: %{"user1" => 4, "user2" => 4}
      }

  """
  def get_comment_stats(treaty_id) do
    comments = from(c in TreatyComment,
      where: c.treaty_id == ^treaty_id,
      select: %{
        id: c.id,
        user_id: c.user_id,
        comment_type: c.comment_type,
        status: c.status
      }
    )
    |> Repo.all()

    stats = Enum.reduce(comments, %{
      total_comments: 0,
      active_comments: 0,
      deleted_comments: 0,
      internal_comments: 0,
      public_comments: 0,
      comments_by_user: %{}
    }, fn comment, acc ->
      updated_acc = %{
        total_comments: acc.total_comments + 1,
        active_comments: if(comment.status == "active", do: acc.active_comments + 1, else: acc.active_comments),
        deleted_comments: if(comment.status == "deleted", do: acc.deleted_comments + 1, else: acc.deleted_comments),
        internal_comments: if(comment.comment_type == "internal_note", do: acc.internal_comments + 1, else: acc.internal_comments),
        public_comments: if(comment.comment_type == "public_note", do: acc.public_comments + 1, else: acc.public_comments),
        comments_by_user: Map.update(acc.comments_by_user, comment.user_id, 1, &(&1 + 1))
      }

      updated_acc
    end)

    stats
  end

  @doc """
  Busca comentários por conteúdo usando LIKE case-insensitive.

  ## Exemplos

      iex> search_comments("urgência")
      [%TreatyComment{}, ...]

      iex> search_comments("cliente", treaty_id)
      [%TreatyComment{}, ...]

  """
  def search_comments(search_term, treaty_id \\ nil) do
    query = from(c in TreatyComment,
      where:
        ilike(c.content, ^"%#{search_term}%") and
        c.status == "active",
      order_by: [desc: c.inserted_at]
    )

    query = if treaty_id do
      from(c in query, where: c.treaty_id == ^treaty_id)
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Retorna um comentário específico por ID, incluindo comentários deletados.

  ## Exemplos

      iex> get_comment!(id)
      %TreatyComment{}

      iex> get_comment!(bad_id)
      ** (Ecto.NoResultsError)

  """
  def get_comment!(id), do: Repo.get!(TreatyComment, id)

  @doc """
  Retorna um comentário específico por ID (versão safe), retornando nil se não encontrado.

  ## Exemplos

      iex> get_comment(id)
      %TreatyComment{}

      iex> get_comment(bad_id)
      nil

  """
  def get_comment(id), do: Repo.get(TreatyComment, id)
end
