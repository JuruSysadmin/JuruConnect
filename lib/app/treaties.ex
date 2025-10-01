defmodule App.Treaties do
  @moduledoc """
  Módulo responsável por gerenciar tratativas.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Treaties.{Treaty, TreatyRating, TreatyActivity}

  @doc """
  Lista todas as tratativas.
  """
  def list_treaties(opts \\ []) do
    Treaty
    |> maybe_filter_by_status(opts[:status])
    |> maybe_filter_by_priority(opts[:priority])
    |> maybe_filter_by_store(opts[:store_id])
    |> maybe_order_by(opts[:order_by])
    |> maybe_limit(opts[:limit])
    |> Repo.all()
  end

  @doc """
  Busca uma tratativa pelo código.
  """
  def get_treaty(treaty_code) when is_binary(treaty_code) do
    case Repo.get_by(Treaty, treaty_code: treaty_code) do
      nil -> {:error, :not_found}
      treaty -> {:ok, treaty}
    end
  end

  @doc """
  Busca uma tratativa pelo código ou cria uma nova se não existir.
  """
  def get_or_create_treaty(treaty_code, attrs \\ %{}) when is_binary(treaty_code) do
    case get_treaty(treaty_code) do
      {:ok, treaty} -> {:ok, treaty}
      {:error, :not_found} -> create_treaty(Map.put(attrs, :treaty_code, treaty_code))
    end
  end

  @doc """
  Cria uma nova tratativa.
  """
  def create_treaty(attrs \\ %{}) do
    %Treaty{}
    |> Treaty.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Atualiza uma tratativa.
  """
  def update_treaty(%Treaty{} = treaty, attrs) do
    treaty
    |> Treaty.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deleta uma tratativa.
  """
  def delete_treaty(%Treaty{} = treaty) do
    Repo.delete(treaty)
  end

  @doc """
  Encerra uma tratativa.
  """
  def close_treaty(%Treaty{} = treaty, user_id, attrs \\ %{}) do
    close_attrs = Map.merge(attrs, %{
      status: "closed",
      closed_at: DateTime.utc_now(),
      closed_by: user_id
    })

    with {:ok, updated_treaty} <- update_treaty(treaty, close_attrs) do
      # Registrar atividade de encerramento
      record_activity(updated_treaty.id, user_id, "closed",
        "Tratativa encerrada", %{close_reason: attrs[:close_reason]})

      {:ok, updated_treaty}
    end
  end

  @doc """
  Reabre uma tratativa encerrada.
  """
  def reopen_treaty(%Treaty{} = treaty, user_id) do
    reopen_attrs = %{
      status: "active",
      closed_at: nil,
      closed_by: nil,
      close_reason: nil
    }

    with {:ok, updated_treaty} <- update_treaty(treaty, reopen_attrs) do
      # Registrar atividade de reabertura
      record_activity(updated_treaty.id, user_id, "reopened",
        "Tratativa reaberta")

      {:ok, updated_treaty}
    end
  end

  @doc """
  Adiciona um rating a uma tratativa.
  """
  def add_rating(treaty_id, user_id, rating, comment \\ nil) do
    rating_attrs = %{
      treaty_id: treaty_id,
      user_id: user_id,
      rating: rating,
      comment: comment
    }

    with {:ok, rating} <- create_rating(rating_attrs) do
      # Registrar atividade de rating
      record_activity(treaty_id, user_id, "rated",
        "Avaliação '#{rating}' adicionada", %{rating: rating})

      {:ok, rating}
    end
  end

  @doc """
  Cria um novo rating.
  """
  def create_rating(attrs \\ %{}) do
    %TreatyRating{}
    |> TreatyRating.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Atualiza um rating existente.
  """
  def update_rating(%TreatyRating{} = rating, attrs) do
    rating
    |> TreatyRating.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Busca ratings de uma tratativa.
  """
  def get_treaty_ratings(treaty_id) when is_nil(treaty_id), do: []
  def get_treaty_ratings(treaty_id) do
    from(r in TreatyRating,
      where: r.treaty_id == ^treaty_id,
      order_by: [desc: r.rated_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Calcula a média de ratings de uma tratativa.
  """
  def get_treaty_average_rating(treaty_id) when is_nil(treaty_id), do: 0.0
  def get_treaty_average_rating(treaty_id) do
    # Buscar todos os ratings da tratativa
    ratings = from(r in TreatyRating,
      where: r.treaty_id == ^treaty_id,
      select: r.rating
    ) |> Repo.all()

    case ratings do
      [] -> 0.0
      ratings_list ->
        # Converter ratings textuais para valores numéricos
        numeric_ratings = Enum.map(ratings_list, fn
          "péssimo" -> 1
          "ruim" -> 2
          "bom" -> 3
          "excelente" -> 4
          _ -> 0
        end)

        # Calcular média
        if length(numeric_ratings) > 0 do
          sum = Enum.sum(numeric_ratings)
          count = length(numeric_ratings)
          Float.round(sum / count, 1)
        else
          0.0
        end
    end
  end

  @doc """
  Registra uma atividade de uma tratativa.
  """
  def record_activity(treaty_id, user_id, activity_type, description, metadata \\ %{}) do
    activity_attrs = %{
      treaty_id: treaty_id,
      user_id: user_id,
      activity_type: activity_type,
      description: description,
      metadata: metadata
    }

    %TreatyActivity{}
    |> TreatyActivity.create_changeset(activity_attrs)
    |> Repo.insert()
  end

  @doc """
  Busca atividades de uma tratativa.
  """
  def get_treaty_activities(treaty_id, limit \\ 50)
  def get_treaty_activities(treaty_id, _limit) when is_nil(treaty_id), do: []
  def get_treaty_activities(treaty_id, limit) do
    from(a in TreatyActivity,
      where: a.treaty_id == ^treaty_id,
      order_by: [desc: a.activity_at],
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Busca estatísticas de uma tratativa.
  """
  def get_treaty_stats(treaty_id) when is_nil(treaty_id) do
    %{
      message_count: 0,
      rating_count: 0,
      average_rating: 0.0,
      activity_count: 0
    }
  end
  def get_treaty_stats(treaty_id) do
    # Buscar a tratativa para obter o treaty_code
    treaty = Repo.get(Treaty, treaty_id)

    if treaty do
      # Contar mensagens usando o treaty_code
      message_count = from(m in App.Chat.Message,
        where: m.treaty_id == ^treaty.treaty_code,
        select: count()
      ) |> Repo.one() || 0

      # Contar ratings usando o UUID
      rating_count = from(r in TreatyRating,
        where: r.treaty_id == ^treaty_id,
        select: count()
      ) |> Repo.one() || 0

      # Média de ratings
      average_rating = get_treaty_average_rating(treaty_id)

      # Contar atividades usando o UUID
      activity_count = from(a in TreatyActivity,
        where: a.treaty_id == ^treaty_id,
        select: count()
      ) |> Repo.one() || 0

      %{
        message_count: message_count,
        rating_count: rating_count,
        average_rating: average_rating,
        activity_count: activity_count
      }
    else
      %{
        message_count: 0,
        rating_count: 0,
        average_rating: 0.0,
        activity_count: 0
      }
    end
  end


  # Funções auxiliares para queries
  defp maybe_filter_by_status(query, nil), do: query
  defp maybe_filter_by_status(query, status), do: from(t in query, where: t.status == ^status)

  defp maybe_filter_by_priority(query, nil), do: query
  defp maybe_filter_by_priority(query, priority), do: from(t in query, where: t.priority == ^priority)

  defp maybe_filter_by_store(query, nil), do: query
  defp maybe_filter_by_store(query, store_id), do: from(t in query, where: t.store_id == ^store_id)

  defp maybe_order_by(query, nil), do: from(t in query, order_by: [desc: t.inserted_at])
  defp maybe_order_by(query, :title), do: from(t in query, order_by: [asc: t.title])
  defp maybe_order_by(query, :status), do: from(t in query, order_by: [asc: t.status])
  defp maybe_order_by(query, :priority), do: from(t in query, order_by: [asc: t.priority])
  defp maybe_order_by(query, :created), do: from(t in query, order_by: [desc: t.inserted_at])

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: from(t in query, limit: ^limit)

  @doc """
  Calcula estatísticas gerais das tratativas para o dashboard administrativo.
  """
  def get_admin_dashboard_stats do
    %{
      total_treaties: get_total_treaties_count(),
      active_treaties: get_active_treaties_count(),
      closed_treaties: get_closed_treaties_count(),
      average_resolution_time: get_average_resolution_time(),
      most_common_close_reasons: get_most_common_close_reasons(),
      reopen_rate: get_reopen_rate(),
      treaties_by_status: get_treaties_by_status(),
      recent_activities: get_recent_activities(10)
    }
  end

  @doc """
  Retorna estatísticas resumidas para exibição na home (apenas para admins).
  """
  def get_home_summary_stats do
    %{
      total_treaties: get_total_treaties_count(),
      active_treaties: get_active_treaties_count(),
      closed_treaties: get_closed_treaties_count(),
      reopen_rate: get_reopen_rate(),
      recent_activities_count: get_recent_activities_count(5)
    }
  end

  @doc """
  Retorna estatísticas específicas do usuário para exibição na home.
  """
  def get_user_home_summary_stats(user_id) do
    %{
      user_total_treaties: get_user_treaties_count(user_id),
      user_active_treaties: get_user_active_treaties_count(user_id),
      user_closed_treaties: get_user_closed_treaties_count(user_id),
      user_reopen_rate: get_user_reopen_rate(user_id)
    }
  end

  @doc """
  Conta atividades recentes (últimas 24h).
  """
  def get_recent_activities_count(_limit \\ 5) do
    yesterday = DateTime.utc_now() |> DateTime.add(-24, :hour)

    from(a in TreatyActivity,
      where: a.activity_at >= ^yesterday,
      select: count()
    ) |> Repo.one() || 0
  end

  @doc """
  Conta tratativas criadas pelo usuário.
  """
  def get_user_treaties_count(user_id) do
    from(t in Treaty, where: t.created_by == ^user_id, select: count()) |> Repo.one() || 0
  end

  @doc """
  Conta tratativas ativas criadas pelo usuário.
  """
  def get_user_active_treaties_count(user_id) do
    from(t in Treaty, where: t.created_by == ^user_id and t.status == "active", select: count()) |> Repo.one() || 0
  end

  @doc """
  Conta tratativas encerradas criadas pelo usuário.
  """
  def get_user_closed_treaties_count(user_id) do
    from(t in Treaty, where: t.created_by == ^user_id and t.status == "closed", select: count()) |> Repo.one() || 0
  end

  @doc """
  Calcula a taxa de reabertura das tratativas do usuário.
  """
  def get_user_reopen_rate(user_id) do
    user_closed = get_user_closed_treaties_count(user_id)

    if user_closed == 0 do
      0.0
    else
      user_reopened = from(a in TreatyActivity,
        join: t in Treaty, on: a.treaty_id == t.id,
        where: a.activity_type == "reopened" and t.created_by == ^user_id,
        select: fragment("COUNT(DISTINCT ?)", a.treaty_id)
      ) |> Repo.one() || 0

      Float.round((user_reopened / user_closed) * 100, 2)
    end
  end

  @doc """
  Calcula o tempo médio de resolução das tratativas encerradas.
  """
  def get_average_resolution_time do
    from(t in Treaty,
      where: t.status == "closed" and not is_nil(t.closed_at) and not is_nil(t.inserted_at),
      select: avg(fragment("EXTRACT(EPOCH FROM (? - ?))", t.closed_at, t.inserted_at))
    )
    |> Repo.one()
    |> case do
      nil -> 0.0
      %Decimal{} = seconds ->
        seconds_float = Decimal.to_float(seconds)
        Float.round(seconds_float / 3600, 2) # Converter para horas
      seconds when is_number(seconds) -> Float.round(seconds / 3600, 2) # Converter para horas
      _ -> 0.0
    end
  end

  @doc """
  Retorna os motivos mais comuns de encerramento.
  """
  def get_most_common_close_reasons(limit \\ 5) do
    from(t in Treaty,
      where: t.status == "closed" and not is_nil(t.close_reason),
      group_by: t.close_reason,
      select: %{
        reason: t.close_reason,
        count: count()
      },
      order_by: [desc: count()],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Calcula a taxa de reabertura das tratativas.
  """
  def get_reopen_rate do
    total_closed = get_closed_treaties_count()

    if total_closed == 0 do
      0.0
    else
      reopened_count = from(a in TreatyActivity,
        where: a.activity_type == "reopened",
        select: fragment("COUNT(DISTINCT ?)", a.treaty_id)
      ) |> Repo.one() || 0

      Float.round((reopened_count / total_closed) * 100, 2)
    end
  end

  @doc """
  Conta o total de tratativas.
  """
  def get_total_treaties_count do
    from(t in Treaty, select: count()) |> Repo.one() || 0
  end

  @doc """
  Conta tratativas ativas.
  """
  def get_active_treaties_count do
    from(t in Treaty, where: t.status == "active", select: count()) |> Repo.one() || 0
  end

  @doc """
  Conta tratativas encerradas.
  """
  def get_closed_treaties_count do
    from(t in Treaty, where: t.status == "closed", select: count()) |> Repo.one() || 0
  end

  @doc """
  Retorna distribuição de tratativas por status.
  """
  def get_treaties_by_status do
    from(t in Treaty,
      group_by: t.status,
      select: %{
        status: t.status,
        count: count()
      },
      order_by: [asc: t.status]
    )
    |> Repo.all()
  end

  @doc """
  Retorna atividades recentes do sistema.
  """
  def get_recent_activities(limit \\ 20) do
    from(a in TreatyActivity,
      order_by: [desc: a.activity_at],
      limit: ^limit,
      preload: [:treaty, :user]
    )
    |> Repo.all()
  end

  @doc """
  Cria um via tuple para o Registry do chat.

  ## Parâmetros
    - `treaty_code`: Código da tratativa (string)

  ## Retorna
    - Via tuple para o Registry

  ## Exemplo
      iex> via_tuple("TRT001234")
      {:via, Registry, {App.ChatRegistry, "TRT001234"}}
  """
  def via_tuple(treaty_code) when is_binary(treaty_code),
    do: {:via, Registry, {App.ChatRegistry, treaty_code}}

  @doc """
  Busca o PID de uma sala de chat pelo código da tratativa.

  ## Parâmetros
    - `treaty_code`: Código da tratativa (string)

  ## Retorna
    - `{:ok, pid}` se encontrado
    - `:error` se não encontrado

  ## Exemplo
      iex> get_chat_room_pid("TRT001234")
      {:ok, #PID<0.123.0>}

      iex> get_chat_room_pid("inexistente")
      :error
  """
  def get_chat_room_pid(treaty_code) when is_binary(treaty_code) do
    case Registry.lookup(App.ChatRegistry, treaty_code) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Inicia uma sala de chat para uma tratativa se ela não existir.

  ## Parâmetros
    - `treaty_code`: Código da tratativa (string)

  ## Retorna
    - `{:ok, pid}` se criada com sucesso
    - `{:error, reason}` se houver erro

  ## Exemplo
      iex> start_chat_room("TRT001234")
      {:ok, #PID<0.123.0>}
  """
  def start_chat_room(treaty_code) when is_binary(treaty_code) do
    case get_chat_room_pid(treaty_code) do
      {:ok, pid} -> {:ok, pid}
      :error -> App.Chat.Room.start_link(treaty_code)
    end
  end
end
