defmodule AppWeb.TreatyContext do
  @moduledoc """
  Contexto para lógica de negócio relacionada a tratativas.
  
  Este módulo encapsula toda a lógica de negócio para:
  - Carregamento e validação de tratativas
  - Encerramento e reabertura de tratativas
  - Gerenciamento de tags
  - Avaliações e comentários
  - Atividades e estatísticas
  """

  alias App.Treaties
  alias App.Tags
  alias App.TreatyComments
  alias AppWeb.ChatConfig

  @doc """
  Carrega dados de uma tratativa com fallback para erro.
  
  ## Parâmetros
  - `treaty_id`: ID da tratativa
  
  ## Retorno
  - `treaty` - Dados da tratativa ou estrutura de fallback
  """
  def load_treaty(treaty_id) when is_binary(treaty_id) do
    case Treaties.get_treaty(treaty_id) do
      {:ok, treaty} -> treaty
      {:error, _} ->
        %Treaties.Treaty{
          treaty_code: treaty_id,
          status: "Não encontrado",
          title: "N/A",
          description: "N/A",
          priority: "N/A",
          created_by: nil,
          store_id: nil
        }
    end
  end

  @doc """
  Carrega dados adicionais de uma tratativa.
  
  ## Parâmetros
  - `treaty_id`: ID da tratativa
  
  ## Retorno
  - `map` - Map com tags, ratings, activities, stats e comments
  """
  def load_treaty_additional_data(treaty_id) do
    %{
      treaty_tags: safely_get_treaty_tags(treaty_id),
      treaty_ratings: safely_get_treaty_ratings(treaty_id),
      treaty_activities: safely_get_treaty_activities(treaty_id),
      treaty_stats: safely_get_treaty_stats(treaty_id),
      treaty_comments: safely_get_treaty_comments(treaty_id)
    }
  end

  @doc """
  Encerra uma tratativa com avaliação.
  
  ## Parâmetros
  - `treaty`: Estrutura da tratativa
  - `user_id`: ID do usuário
  - `close_attrs`: Atributos de encerramento
  - `rating_attrs`: Atributos de avaliação
  
  ## Retorno
  - `{:ok, updated_treaty, rating}` - Tratativa encerrada e avaliada
  - `{:ok, updated_treaty, nil}` - Tratativa encerrada sem avaliação
  - `{:error, changeset}` - Erro no encerramento
  """
  def close_treaty_with_rating(treaty, user_id, close_attrs, rating_attrs) do
    with {:ok, updated_treaty} <- Treaties.close_treaty(treaty, user_id, close_attrs) do
      case Treaties.add_rating(updated_treaty.id, user_id, rating_attrs) do
        {:ok, rating} -> {:ok, updated_treaty, rating}
        {:error, _changeset} -> {:ok, updated_treaty, nil}
      end
    end
  end

  @doc """
  Reabre uma tratativa.
  
  ## Parâmetros
  - `treaty`: Estrutura da tratativa
  - `user_id`: ID do usuário
  
  ## Retorno
  - `{:ok, updated_treaty}` - Tratativa reaberta
  - `{:error, changeset}` - Erro na reabertura
  """
  def reopen_treaty(treaty, user_id) do
    Treaties.reopen_treaty(treaty, user_id)
  end

  @doc """
  Adiciona uma tag a uma tratativa.
  
  ## Parâmetros
  - `treaty_id`: ID da tratativa
  - `tag_id`: ID da tag
  - `user_id`: ID do usuário
  
  ## Retorno
  - `{:ok, treaty_tag}` - Tag adicionada
  - `{:error, changeset}` - Erro na adição
  """
  def add_tag_to_treaty(treaty_id, tag_id, user_id) do
    Tags.add_tag_to_treaty(treaty_id, tag_id, user_id)
  end

  @doc """
  Remove uma tag de uma tratativa.
  
  ## Parâmetros
  - `treaty_id`: ID da tratativa
  - `tag_id`: ID da tag
  
  ## Retorno
  - `{count, nil}` - Tag removida (count > 0)
  - `{0, nil}` - Tag não encontrada
  """
  def remove_tag_from_treaty(treaty_id, tag_id) do
    Tags.remove_tag_from_treaty(treaty_id, tag_id)
  end

  @doc """
  Busca tags disponíveis para uma loja.
  
  ## Parâmetros
  - `query`: Query de busca
  - `store_id`: ID da loja
  
  ## Retorno
  - `tags` - Lista de tags encontradas
  """
  def search_tags(query, store_id) do
    if String.length(query) >= ChatConfig.get_config_value(:search, :min_search_length) do
      Tags.search_tags(query, store_id)
    else
      Tags.list_tags(store_id)
    end
  end

  @doc """
  Cria um comentário em uma tratativa.
  
  ## Parâmetros
  - `treaty_id`: ID da tratativa
  - `user_id`: ID do usuário
  - `content`: Conteúdo do comentário
  - `comment_type`: Tipo do comentário
  
  ## Retorno
  - `{:ok, comment}` - Comentário criado
  - `{:error, changeset}` - Erro na criação
  """
  def create_comment(treaty_id, user_id, content, comment_type) do
    TreatyComments.create_comment(%{
      treaty_id: treaty_id,
      user_id: user_id,
      content: content,
      comment_type: comment_type
    })
  end

  @doc """
  Atualiza um comentário.
  
  ## Parâmetros
  - `comment_id`: ID do comentário
  - `content`: Novo conteúdo
  
  ## Retorno
  - `{:ok, comment}` - Comentário atualizado
  - `{:error, :not_found}` - Comentário não encontrado
  - `{:error, changeset}` - Erro na atualização
  """
  def update_comment(comment_id, content) do
    TreatyComments.update_comment(comment_id, %{content: content})
  end

  @doc """
  Remove um comentário.
  
  ## Parâmetros
  - `comment_id`: ID do comentário
  
  ## Retorno
  - `{:ok, comment}` - Comentário removido
  - `{:error, :not_found}` - Comentário não encontrado
  """
  def delete_comment(comment_id) do
    TreatyComments.delete_comment(comment_id)
  end

  @doc """
  Verifica se um usuário pode encerrar uma tratativa.
  
  ## Parâmetros
  - `user`: Estrutura do usuário
  - `treaty`: Estrutura da tratativa
  
  ## Retorno
  - `true` - Pode encerrar
  - `false` - Não pode encerrar
  """
  def can_close_treaty?(user, treaty) do
    App.Accounts.can_close_treaty?(user, treaty)
  end

  @doc """
  Obtém classes CSS para status da tratativa.
  
  ## Parâmetros
  - `status`: Status da tratativa
  
  ## Retorno
  - `classes` - String com classes CSS
  """
  def get_status_classes(status) do
    base_classes = "px-2.5 py-1 text-xs font-semibold rounded-full border shadow-sm transition-all duration-200"
    
    case status do
      "active" -> base_classes <> " bg-emerald-50 text-emerald-700 border-emerald-200 hover:bg-emerald-100"
      "inactive" -> base_classes <> " bg-amber-50 text-amber-700 border-amber-200 hover:bg-amber-100"
      "cancelled" -> base_classes <> " bg-red-50 text-red-700 border-red-200 hover:bg-red-100"
      "completed" -> base_classes <> " bg-blue-50 text-blue-700 border-blue-200 hover:bg-blue-100"
      "closed" -> base_classes <> " bg-gray-50 text-gray-700 border-gray-200 hover:bg-gray-100"
      _ -> base_classes <> " bg-gray-50 text-gray-700 border-gray-200 hover:bg-gray-100"
    end
  end

  # Funções privadas

  defp safely_get_treaty_tags(treaty_id) do
    try do
      Tags.get_treaty_tags(treaty_id)
    rescue
      _ -> []
    end
  end

  defp safely_get_treaty_ratings(treaty_id) do
    try do
      Treaties.get_treaty_ratings(treaty_id)
    rescue
      _ -> []
    end
  end

  defp safely_get_treaty_activities(treaty_id) do
    try do
      limit = ChatConfig.get_config_value(:activities, :default_limit)
      Treaties.get_treaty_activities(treaty_id, limit)
    rescue
      _ -> []
    end
  end

  defp safely_get_treaty_stats(treaty_id) do
    try do
      Treaties.get_treaty_stats(treaty_id)
    rescue
      _ -> %{}
    end
  end

  defp safely_get_treaty_comments(treaty_id) do
    try do
      TreatyComments.get_treaty_comments(treaty_id)
    rescue
      _ -> []
    end
  end
end
