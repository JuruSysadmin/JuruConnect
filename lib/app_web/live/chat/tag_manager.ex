defmodule AppWeb.ChatLive.TagManager do
  @moduledoc """
  Manager responsável exclusivamente pelo gerenciamento de tags no chat.

  Este módulo centraliza toda a lógica relacionada a:
  - Exibição e controle de modais de tags
  - Busca e filtragem de tags
  - Adição e remoção de tags de tratativas
  - Atualização de estado relacionado a tags
  - Broadcast de mudanças de tags
  """

  use Phoenix.LiveView
  alias App.Tags
  alias AppWeb.ChatConfig

  @doc """
  Inicializa o estado relacionado a tags no socket.
  """
  def initialize_tag_state(socket) do
    socket
    |> assign(:show_tag_modal, false)
    |> assign(:tag_search_query, "")
    |> assign(:tag_search_results, [])
  end

  @doc """
  Carrega as tags da tratativa atual.
  """
  def load_treaty_tags(socket, treaty_id) do
    treaty_tags = safely_get_treaty_tags(treaty_id)
    assign(socket, :treaty_tags, treaty_tags)
  end

  @doc """
  Exibe o modal de gerenciamento de tags.
  """
  def show_tag_modal(socket) do
    all_tags = Tags.list_tags(socket.assigns.user_object.store_id)

    socket
    |> assign(:show_tag_modal, true)
    |> assign(:modal_animation_state, "opening")
    |> assign(:tag_search_results, all_tags)
    |> assign(:tag_search_query, "")
    |> push_event("modal-opening", %{modal: "tag"})
  end

  @doc """
  Oculta o modal de gerenciamento de tags com animação.
  """
  def hide_tag_modal(socket) do
    socket
    |> assign(:modal_animation_state, "closing")
    |> push_event("modal-closing", %{modal: "tag"})
    |> then(fn socket ->
      Process.send_after(self(), :close_tag_modal, 300)
      socket
    end)
  end

  def search_tags(socket, %{"query" => query}) do
    if String.length(query) >= ChatConfig.get_config_value(:search, :min_search_length) do
      results = Tags.search_tags(query, socket.assigns.user_object.store_id)
      socket
      |> assign(:tag_search_query, query)
      |> assign(:tag_search_results, results)
    else
      socket
      |> assign(:tag_search_query, query)
      |> assign(:tag_search_results, [])
    end
  end

  def search_tags(socket, %{"value" => query}) do
    if String.length(query) >= ChatConfig.get_config_value(:search, :min_search_length) do
      results = Tags.search_tags(query, socket.assigns.user_object.store_id)
      socket
      |> assign(:tag_search_query, query)
      |> assign(:tag_search_results, results)
    else
      all_tags = Tags.list_tags(socket.assigns.user_object.store_id)
      socket
      |> assign(:tag_search_query, query)
      |> assign(:tag_search_results, all_tags)
    end
  end

  @doc """
  Adiciona uma tag à tratativa atual.
  """
  def add_tag_to_treaty(socket, %{"tag_id" => tag_id}) do
    user_id = socket.assigns.user_object.id

    case Tags.add_tag_to_treaty(socket.assigns.treaty_id, tag_id, user_id) do
      {:ok, _treaty_tag} ->
        treaty_tags = Tags.get_treaty_tags(socket.assigns.treaty_id)

        # Broadcast da atualização para outros usuários
        Phoenix.PubSub.broadcast(
          App.PubSub,
          socket.assigns.topic,
          {:treaty_tags_updated, treaty_tags}
        )

        socket
        |> assign(:treaty_tags, treaty_tags)
        |> assign(:show_tag_modal, false)
        |> assign(:tag_search_query, "")
        |> assign(:tag_search_results, [])
        |> push_event("show-toast", %{
          type: "success",
          title: "Tag adicionada!",
          message: "A tag foi adicionada com sucesso à tratativa.",
          duration: ChatConfig.get_config_value(:notifications, :toast_duration)[:success]
        })

      {:error, _changeset} ->
        socket
        |> push_event("show-toast", %{
          type: "error",
          title: "Erro ao adicionar tag",
          message: "Não foi possível adicionar a tag. Tente novamente.",
          duration: ChatConfig.get_config_value(:notifications, :toast_duration)[:error]
        })
    end
  end

  @doc """
  Remove uma tag da tratativa atual.
  """
  def remove_tag_from_treaty(socket, %{"tag_id" => tag_id}) do
    case Tags.remove_tag_from_treaty(socket.assigns.treaty_id, tag_id) do
      {count, nil} when count > 0 ->
        treaty_tags = Tags.get_treaty_tags(socket.assigns.treaty_id)

        # Broadcast da atualização para outros usuários
        Phoenix.PubSub.broadcast(
          App.PubSub,
          socket.assigns.topic,
          {:treaty_tags_updated, treaty_tags}
        )

        socket
        |> assign(:treaty_tags, treaty_tags)
        |> push_event("show-toast", %{
          type: "success",
          title: "Tag removida!",
          message: "A tag foi removida com sucesso da tratativa.",
          duration: 3000
        })

      _ ->
        socket
        |> push_event("show-toast", %{
          type: "error",
          title: "Erro ao remover tag",
          message: "Não foi possível remover a tag. Tente novamente.",
          duration: 5000
        })
    end
  end

  @doc """
  Processa atualizações de tags recebidas via broadcast.
  """
  def handle_tags_updated(socket, treaty_tags) do
    assign(socket, :treaty_tags, treaty_tags)
  end

  @doc """
  Fecha o modal de tags após a animação.
  """
  def close_tag_modal(socket) do
    socket
    |> assign(:show_tag_modal, false)
    |> assign(:modal_animation_state, "closed")
    |> assign(:tag_search_query, "")
    |> assign(:tag_search_results, [])
  end

  # Funções privadas

  defp safely_get_treaty_tags(treaty_id) do
    try do
      Tags.get_treaty_tags(treaty_id)
    rescue
      _ -> []
    end
  end
end
