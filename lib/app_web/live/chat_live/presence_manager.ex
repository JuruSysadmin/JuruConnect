defmodule AppWeb.ChatLive.PresenceManager do
  @moduledoc """
  Gerenciador de presença para o chat em tempo real.

  Este módulo contém toda a lógica relacionada ao rastreamento de presença
  de usuários, notificações de entrada/saída e cache de eventos extraída
  do AppWeb.ChatLive para melhorar a organização e eliminar anti-padrões.

  ## Funcionalidades
  - Setup e tracking de presença de usuários
  - Sistema de notificações de entrada/saída
  - Cache inteligente para evitar spam de notificações
  - Extração e processamento de dados de usuários
  - Limpeza automática de cache expirado
  - Debounce de reconexões rápidas

  ## Anti-padrões Corrigidos
  - Long parameter list: Parâmetros agrupados em structs especializados
  - Primitive obsession: Types definidos ao invés de strings/maps
  - Complex extractions: with pipeline e pattern matching assertivo
  - Comments overuse: Logs limpos sem emojis desnecessários
  - Non-assertive pattern matching: Pattern matching direto
  """

  require Logger
  alias AppWeb.Presence
  alias App.ChatConfig
  alias Phoenix.PubSub

  @type presence_event :: :join | :leave
  @type notification_result :: {:ok, map()} | {:error, String.t()}
  @type cache_result :: {:recent_join, integer()} | {:recent_leave, integer()} | nil

  defmodule PresenceConfig do
    @moduledoc """
    Estrutura para configuração de presença.
    Elimina o anti-padrão Long parameter list.
    """

    @type t :: %__MODULE__{
      topic: String.t(),
      user_id: String.t(),
      user_name: String.t(),
      socket: Phoenix.LiveView.Socket.t(),
      order_id: String.t()
    }

    defstruct [:topic, :user_id, :user_name, :socket, :order_id]
  end

  defmodule UserPresence do
    @moduledoc """
    Estrutura para dados de presença de usuário.
    Elimina primitive obsession normalizando dados de usuário.
    """

    @type t :: %__MODULE__{
      user_id: String.t(),
      name: String.t(),
      joined_at: String.t(),
      user_agent: String.t(),
      socket_id: String.t(),
      pid: String.t()
    }

    defstruct [:user_id, :name, :joined_at, :user_agent, :socket_id, :pid]

    def new(user_id, user_name, socket) do
      %__MODULE__{
        user_id: user_id,
        name: user_name,
        joined_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        user_agent: Phoenix.LiveView.get_connect_info(socket, :user_agent) || "Unknown",
        socket_id: socket.id,
        pid: inspect(self())
      }
    end
  end

  defmodule PresenceChange do
    @moduledoc """
    Estrutura para mudanças de presença.
    Agrupa dados relacionados eliminando Long parameter list.
    """

    @type t :: %__MODULE__{
      joins: map(),
      leaves: map(),
      topic: String.t(),
      socket: Phoenix.LiveView.Socket.t()
    }

    defstruct [:joins, :leaves, :topic, :socket]
  end

  defmodule NotificationEvent do
    @moduledoc """
    Estrutura para eventos de notificação.
    Normaliza dados de notificação eliminando primitive obsession.
    """

    @type presence_event :: :join | :leave

    @type t :: %__MODULE__{
      user_id: String.t(),
      user_name: String.t(),
      event_type: presence_event(),
      timestamp: integer(),
      topic: String.t()
    }

    defstruct [:user_id, :user_name, :event_type, :timestamp, :topic]
  end

  # ========================================
  # PRESENCE SETUP - API Principal
  # ========================================

  @doc """
  Configura presença se conectado usando estrutura unificada.
  Elimina Long parameter list agrupando parâmetros relacionados.
  """
  @spec setup_presence_if_connected(PresenceConfig.t()) :: :ok | {:error, term()}
  def setup_presence_if_connected(%PresenceConfig{} = config) do
    if Phoenix.LiveView.connected?(config.socket) do
      setup_presence_tracking(config)
    else
      :ok
    end
  end

  @doc """
  Constrói configuração de presença a partir de parâmetros.
  Centraliza construção eliminando duplicação de código.
  """
  @spec build_presence_config(Phoenix.LiveView.Socket.t(), String.t(), String.t()) :: PresenceConfig.t()
  def build_presence_config(socket, topic, order_id) do
    current_user_name = resolve_current_user_name(socket)
    current_user_id = resolve_unique_user_id(socket)

    %PresenceConfig{
      topic: topic,
      user_id: current_user_id,
      user_name: current_user_name,
      socket: socket,
      order_id: order_id
    }
  end

  # ========================================
  # USER EXTRACTION
  # ========================================

  @doc """
  Extrai usuários únicos de presenças usando pattern matching assertivo.
  Elimina Complex extractions in clauses.
  """
  @spec extract_unique_users_from_presences(map()) :: [String.t()]
  def extract_unique_users_from_presences(presences) do
    try do
      unique_users = presences
      |> Map.values()
      |> Enum.flat_map(&extract_users_from_metas/1)
      |> Enum.uniq_by(fn {user_id, _name} -> user_id end)
      |> Enum.map(fn {_user_id, display_name} -> display_name end)
      |> Enum.sort()

      log_user_extraction_result(unique_users)
      unique_users
    rescue
      error ->
        Logger.error("Error extracting users from presences: #{inspect(error)}")
        []
    end
  end

  # ========================================
  # PRESENCE CHANGE PROCESSING
  # ========================================

  @doc """
  Processa mudanças de presença usando with pipeline.
  Elimina Complex extractions in clauses.
  """
  @spec process_presence_change(PresenceChange.t()) :: :ok
  def process_presence_change(%PresenceChange{} = change) do
    start_time = System.monotonic_time(:microsecond)

    with :ok <- process_presence_joins(change),
         :ok <- process_presence_leaves(change) do
      log_presence_processing_time(start_time, change.topic, map_size(change.joins) + map_size(change.leaves))
      :ok
    else
      error ->
        Logger.error("Error processing presence change: #{inspect(error)}")
        :ok
    end
  end

  # ========================================
  # NOTIFICATION MANAGEMENT
  # ========================================

  @doc """
  Verifica se deve criar notificação de entrada usando pattern matching assertivo.
  Elimina Complex extractions in clauses com debounce robusto.
  """
  @spec should_create_join_notification?(String.t(), String.t()) :: boolean()
  def should_create_join_notification?(user_id, user_name) do
    current_time = System.system_time(:second)

    case get_user_notification_cache(user_id) do
      {:recent_join, timestamp} when current_time - timestamp < 30 ->
        log_duplicate_notification_blocked(user_name, current_time - timestamp)
        false

      {:recent_leave, timestamp} when current_time - timestamp < 15 ->
        log_quick_reconnection_detected(user_name, current_time - timestamp)
        false

      _ ->
        process_valid_join_notification(user_id, user_name, current_time)
    end
  end

  @doc """
  Verifica se deve criar notificação de saída usando pattern matching assertivo.
  Elimina primitive obsession com types bem definidos.
  """
  @spec should_create_leave_notification?(String.t(), String.t(), String.t()) :: boolean()
  def should_create_leave_notification?(user_name, user_id, topic) do
    current_time = System.system_time(:second)

    case get_user_notification_cache(user_id) do
      {:recent_leave, timestamp} when current_time - timestamp < 15 ->
        Logger.debug("Leave notification blocked for #{user_name}: #{current_time - timestamp}s since last leave")
        false

      _ ->
        process_valid_leave_notification(user_id, user_name, topic, current_time)
    end
  end

  # ========================================
  # CACHE MANAGEMENT
  # ========================================

  @doc """
  Obtém cache de notificação do usuário usando pattern matching assertivo.
  Normaliza retornos conforme anti-padrões do Elixir.
  """
  @spec get_user_notification_cache(String.t()) :: cache_result()
  def get_user_notification_cache(user_id) do
    join_cache = Process.get({:last_join, user_id})
    leave_cache = Process.get({:last_leave, user_id})

    case {join_cache, leave_cache} do
      {join_time, leave_time} when is_integer(join_time) and is_integer(leave_time) ->
        if join_time > leave_time do
          {:recent_join, join_time}
        else
          {:recent_leave, leave_time}
        end

      {join_time, nil} when is_integer(join_time) ->
        {:recent_join, join_time}

      {nil, leave_time} when is_integer(leave_time) ->
        {:recent_leave, leave_time}

      _ ->
        nil
    end
  end

  @doc """
  Limpa cache de notificações expirado.
  Remove entradas antigas automaticamente.
  """
  @spec cleanup_notification_cache() :: :ok
  def cleanup_notification_cache do
    current_time = System.system_time(:second)

    Process.get_keys()
    |> Enum.filter(&is_notification_cache_key?/1)
    |> Enum.each(fn key ->
      if is_cache_entry_expired?(key, current_time) do
        Process.delete(key)
      end
    end)

    :ok
  end

  # ========================================
  # PRIVATE FUNCTIONS
  # ========================================

  # Setup de rastreamento de presença
  defp setup_presence_tracking(%PresenceConfig{} = config) do
    with :ok <- subscribe_to_topics(config),
         {:ok, _} <- track_user_presence(config) do
      schedule_message_reload()
      :ok
    else
      {:error, reason} ->
        Logger.warning("Failed to track presence for user #{config.user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Subscrição a tópicos necessários
  defp subscribe_to_topics(%PresenceConfig{} = config) do
    topics = [
      config.topic,
      "notifications:#{config.user_id}",
      "sound_notifications:#{config.user_id}",
      "mentions:#{config.user_id}"
    ]

    Enum.each(topics, &PubSub.subscribe(App.PubSub, &1))
    Logger.debug("Subscribed to topics for user: #{config.user_name} (#{config.user_id})")
    :ok
  end

  # Rastreamento de presença do usuário
  defp track_user_presence(%PresenceConfig{} = config) do
    user_data = UserPresence.new(config.user_id, config.user_name, config.socket)

    Logger.debug("Tracking presence for user: #{config.user_name} (#{config.user_id}) on topic: #{config.topic}")

    case Presence.track(self(), config.topic, config.user_id, Map.from_struct(user_data)) do
      {:ok, _} ->
        Logger.debug("Presence tracking successful for user: #{config.user_id}")
        {:ok, user_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Agendamento de recarregamento de mensagens
  defp schedule_message_reload do
    Process.send_after(self(), :reload_historical_messages, 500)
    Logger.info("Scheduled historical message reload for connected user")
  end

  # Extração de usuários de metas
  defp extract_users_from_metas(%{metas: user_metas}) do
    Enum.map(user_metas, &extract_user_info_from_meta/1)
  end

  # Extração de informações de usuário usando pattern matching assertivo
  defp extract_user_info_from_meta(%{name: name, user_id: user_id})
    when is_binary(name) and is_binary(user_id), do: {user_id, name}

  defp extract_user_info_from_meta(%{"name" => name, "user_id" => user_id})
    when is_binary(name) and is_binary(user_id), do: {user_id, name}

  defp extract_user_info_from_meta(%{name: name}) when is_binary(name), do: {name, name}

  defp extract_user_info_from_meta(%{"name" => name}) when is_binary(name), do: {name, name}

  defp extract_user_info_from_meta(name) when is_binary(name), do: {name, name}

  defp extract_user_info_from_meta(_) do
    default_user = ChatConfig.default_username()
    {default_user, default_user}
  end

  # Log de resultado da extração de usuários
  defp log_user_extraction_result(users) do
    Logger.debug("Extracted #{length(users)} unique users from presences: #{inspect(users)}")
  end

  # Processamento de entradas de presença
  defp process_presence_joins(%PresenceChange{joins: joins, topic: topic, socket: socket}) do
    if map_size(joins) > 0 do
      broadcast_user_join_notifications(joins, topic, socket)
    end
    :ok
  end

  # Processamento de saídas de presença
  defp process_presence_leaves(%PresenceChange{leaves: leaves, topic: topic, socket: socket}) do
    if map_size(leaves) > 0 do
      broadcast_user_leave_notifications(leaves, topic, socket)
    end
    :ok
  end

  # Broadcast de notificações de entrada
  defp broadcast_user_join_notifications(joins, topic, _socket) do
    Enum.each(joins, fn {_user_id, %{metas: [meta | _]}} ->
      user_name = extract_user_name_from_meta(meta)
      user_id = Map.get(meta, :user_id, Map.get(meta, "user_id", "unknown"))

      process_user_join_notification(user_name, user_id, topic)
    end)
  end

  # Processamento de notificação de entrada
  defp process_user_join_notification(user_name, user_id, topic) do
    if should_create_join_notification?(user_id, user_name) do
      create_and_broadcast_join_notification(user_name, topic)
    end
  end

  # Broadcast de notificações de saída
  defp broadcast_user_leave_notifications(leaves, topic, _socket) do
    Enum.each(leaves, fn {_user_id, %{metas: [meta | _]}} ->
      user_name = extract_user_name_from_meta(meta)
      user_id = Map.get(meta, :user_id, Map.get(meta, "user_id", "unknown"))

      if should_create_leave_notification?(user_name, user_id, topic) do
        create_and_broadcast_leave_notification(user_name, topic)
      end
    end)
  end

  # Extração de nome de usuário de meta usando pattern matching
  defp extract_user_name_from_meta(%{name: name}) when is_binary(name), do: name
  defp extract_user_name_from_meta(%{"name" => name}) when is_binary(name), do: name
  defp extract_user_name_from_meta(meta) when is_map(meta) do
    Map.get(meta, :user_id, Map.get(meta, "user_id", "Usuário"))
  end
  defp extract_user_name_from_meta(_), do: "Usuário"

  # Criação e broadcast de notificação de entrada
  defp create_and_broadcast_join_notification(user_name, topic) do
    start_time = System.monotonic_time(:microsecond)

    notification = %{
      id: "system_#{System.unique_integer([:positive])}",
      text: "#{user_name} entrou no chat",
      sender_name: "Sistema",
      sender_id: "system",
      inserted_at: DateTime.utc_now(),
      is_system: true,
      tipo: :system_notification,
      mentions: [],
      image_url: nil,
      status: :system
    }

    PubSub.broadcast(App.PubSub, topic, {:system_notification, notification})
    log_notification_timing(start_time, :join, notification.text)
  end

  # Criação e broadcast de notificação de saída
  defp create_and_broadcast_leave_notification(user_name, topic) do
    start_time = System.monotonic_time(:microsecond)

    notification = %{
      id: "system_#{System.unique_integer([:positive])}",
      text: "#{user_name} saiu do chat",
      sender_name: "Sistema",
      sender_id: "system",
      inserted_at: DateTime.utc_now(),
      is_system: true,
      tipo: :system_notification,
      mentions: [],
      image_url: nil,
      status: :system
    }

    PubSub.broadcast(App.PubSub, topic, {:system_notification, notification})
    log_notification_timing(start_time, :leave, notification.text)
  end

  # Log de timing de notificação
  defp log_notification_timing(start_time, notification_type, message_text) do
    end_time = System.monotonic_time(:microsecond)
    duration_ms = (end_time - start_time) / 1000

    Logger.debug("FAST notification created and broadcast in #{Float.round(duration_ms, 2)}ms - #{notification_type}: #{message_text}")
  end

  # Processamento de notificação válida de entrada
  defp process_valid_join_notification(user_id, user_name, current_time) do
    Process.put({:last_join, user_id}, current_time)
    Logger.debug("Valid join notification for #{user_name}")
    true
  end

  # Processamento de notificação válida de saída
  defp process_valid_leave_notification(user_id, user_name, _topic, current_time) do
    Process.put({:last_leave, user_id}, current_time)
    Logger.debug("Valid leave notification for #{user_name}")
    true
  end

  # Log de notificação duplicada bloqueada
  defp log_duplicate_notification_blocked(user_name, time_diff) do
    Logger.debug("Duplicate notification blocked for #{user_name}: #{time_diff}s since last join")
  end

  # Log de reconexão rápida detectada
  defp log_quick_reconnection_detected(user_name, time_diff) do
    Logger.debug("Quick reconnection detected for #{user_name}: #{time_diff}s - avoiding spam")
  end

  # Log de tempo de processamento de presença
  defp log_presence_processing_time(start_time, topic, change_count) do
    end_time = System.monotonic_time(:microsecond)
    duration_ms = (end_time - start_time) / 1000

    Logger.debug("Processed #{change_count} presence changes for #{topic} in #{Float.round(duration_ms, 2)}ms")
  end

  # Verificação se é chave de cache de notificação
  defp is_notification_cache_key?({:last_join, _user_id}), do: true
  defp is_notification_cache_key?({:last_leave, _user_id}), do: true
  defp is_notification_cache_key?(_), do: false

  # Verificação se entrada de cache está expirada
  defp is_cache_entry_expired?(key, current_time) do
    case Process.get(key) do
      timestamp when is_integer(timestamp) ->
        current_time - timestamp > 300  # 5 minutos
      _ ->
        true
    end
  end

  # Resolução de nome de usuário atual
  defp resolve_current_user_name(socket) do
    current_user = socket.assigns[:current_user]
    extract_user_name(current_user)
  end

  # Resolução de ID único de usuário
  defp resolve_unique_user_id(socket) do
    current_user = socket.assigns[:current_user]
    user_id = extract_user_id(current_user)

    Logger.debug("User ID resolved: #{user_id} from assigns: #{inspect(current_user)}")
    user_id
  end

  # Extração de nome de usuário usando pattern matching assertivo
  defp extract_user_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp extract_user_name(%{username: username}) when is_binary(username) and username != "", do: username
  defp extract_user_name(%{"name" => name}) when is_binary(name) and name != "", do: name
  defp extract_user_name(%{"username" => username}) when is_binary(username) and username != "", do: username
  defp extract_user_name(username) when is_binary(username) and username != "", do: username
  defp extract_user_name(_), do: ChatConfig.default_username()

  # Extração de ID de usuário usando pattern matching assertivo
  defp extract_user_id(%{id: id}) when is_binary(id) and id != "", do: id
  defp extract_user_id(%{"id" => id}) when is_binary(id) and id != "", do: id
  defp extract_user_id(%{username: username}) when is_binary(username) and username != "", do: "user_#{username}"
  defp extract_user_id(%{"username" => username}) when is_binary(username) and username != "", do: "user_#{username}"
  defp extract_user_id(username) when is_binary(username) and username != "", do: "legacy_#{username}"
  defp extract_user_id(_), do: generate_anonymous_user_id()

  # Geração de ID anônimo
  defp generate_anonymous_user_id do
    "anonymous_#{System.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end
end
