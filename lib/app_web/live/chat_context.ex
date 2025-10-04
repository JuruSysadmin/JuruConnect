defmodule AppWeb.ChatContext do
  @moduledoc """
  Contexto para lógica de negócio relacionada a mensagens e comunicação em chat.

  Este módulo encapsula toda a lógica de negócio para:
  - Envio e validação de mensagens
  - Carregamento de histórico de mensagens
  - Processamento de uploads de arquivos
  - Gerenciamento de read receipts
  - Notificações e menções
  """

  alias App.Chat
  alias AppWeb.ChatConfig

  @doc """
  Valida uma mensagem antes do envio.

  ## Parâmetros
  - `text`: Texto da mensagem
  - `socket`: Socket do LiveView
  - `uploads`: Uploads pendentes

  ## Retorno
  - `{:ok, :valid}` - Mensagem válida
  - `{:error, reason}` - Erro de validação
  """
  def validate_message(text, socket, uploads \\ %{}) do
    with {:ok, _} <- validate_message_not_empty(text, uploads),
         {:ok, _} <- validate_message_length(text),
         {:ok, _} <- validate_connection(socket),
         {:ok, _} <- validate_treaty_status(socket) do
      {:ok, :valid}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Processa o envio de uma mensagem.

  ## Parâmetros
  - `treaty_id`: ID da tratativa
  - `user_id`: ID do usuário
  - `text`: Texto da mensagem
  - `file_info`: Informações do arquivo (se houver)

  ## Retorno
  - `{:ok, message}` - Mensagem enviada com sucesso
  - `{:error, changeset}` - Erro no envio
  """
  def send_message(treaty_id, user_id, text, file_info \\ nil) do
    Chat.send_message(treaty_id, user_id, text, file_info)
  end

  @doc """
  Carrega mensagens paginadas para uma tratativa.

  ## Parâmetros
  - `treaty_id`: ID da tratativa
  - `limit`: Limite de mensagens (opcional)
  - `offset`: Offset para paginação (opcional)

  ## Retorno
  - `{:ok, messages, has_more}` - Mensagens carregadas
  - `{:error, reason}` - Erro no carregamento
  """
  def load_messages(treaty_id, limit \\ nil, offset \\ 0) do
    limit = limit || ChatConfig.get_config_value(:messages, :default_message_limit)

    try do
      case Chat.list_messages_for_treaty(treaty_id, limit, offset) do
        {:ok, messages, has_more} -> {:ok, messages, has_more}
        other -> {:error, "Unexpected result: #{inspect(other)}"}
      end
    rescue
      error -> {:error, "Failed to load messages: #{inspect(error)}"}
    end
  end

  @doc """
  Processa upload de arquivo e retorna informações estruturadas.

  ## Parâmetros
  - `socket`: Socket do LiveView com uploads
  - `upload_type`: Tipo do upload (:image)

  ## Retorno
  - `nil` - Nenhum upload
  - `file_info` - Informações do arquivo processado
  """
  def process_upload(socket, upload_type \\ :image) do
    entries = socket.assigns.uploads[upload_type].entries

    case entries do
      [] ->
        nil
      [_entry | _] ->
        consume_uploaded_entries(socket, upload_type, &process_upload_entry/2)
        |> Enum.filter(&(&1 != nil))
    end
  end

  @doc """
  Marca mensagens como lidas.

  ## Parâmetros
  - `message_ids`: Lista de IDs das mensagens
  - `user_id`: ID do usuário
  - `treaty_id`: ID da tratativa

  ## Retorno
  - `:ok` - Operação concluída
  """
  def mark_messages_as_read(message_ids, user_id, treaty_id) do
    Enum.each(message_ids, fn message_id ->
      safe_mark_message_as_read(message_id, user_id, treaty_id)
    end)
  end

  @doc """
  Obtém read receipts para mensagens específicas.

  ## Parâmetros
  - `message_ids`: Lista de IDs das mensagens
  - `treaty_id`: ID da tratativa

  ## Retorno
  - `read_receipts` - Map com read receipts
  """
  def get_read_receipts(message_ids, treaty_id) do
    try do
      Chat.get_read_receipts_for_messages(message_ids, treaty_id)
    rescue
      _ -> %{}
    end
  end

  @doc """
  Formata texto com menções destacadas.

  ## Parâmetros
  - `text`: Texto a ser formatado

  ## Retorno
  - `formatted_html` - HTML formatado com menções
  """
  def format_message_with_mentions(text) when is_binary(text) do
    text
    |> String.replace(~r/@([\w\.-]+)/, ~s(<span class="bg-blue-100 text-blue-800 px-1.5 py-0.5 rounded-md text-xs font-medium">@\\1</span>))
    |> Phoenix.HTML.raw()
  end
  def format_message_with_mentions(_), do: ""

  @doc """
  Obtém informações do usuário para mensagem.

  ## Parâmetros
  - `socket`: Socket do LiveView

  ## Retorno
  - `{user_id, user_name}` - ID e nome do usuário
  """
  def get_user_info_for_message(socket) do
    case socket.assigns do
      %{user_object: nil, current_user: current_user} ->
        {nil, current_user}
      %{user_object: %{id: id, name: name}, current_user: _} when not is_nil(name) ->
        {id, name}
      %{user_object: %{id: id, username: username}, current_user: _} when not is_nil(username) ->
        {id, username}
      %{user_object: %{id: id}, current_user: current_user} ->
        {id, current_user}
    end
  end

  # Funções privadas

  defp validate_message_not_empty("", %{image: %{entries: []}}) do
    {:error, "Digite uma mensagem ou selecione uma imagem"}
  end
  defp validate_message_not_empty("", _uploads), do: {:ok, :valid}
  defp validate_message_not_empty(_text, _uploads), do: {:ok, :valid}

  defp validate_message_length(text) when is_binary(text) and byte_size(text) > 0 do
    max_length = ChatConfig.get_config_value(:security, :max_message_length)

    case byte_size(text) > max_length do
      true -> {:error, "Mensagem muito longa"}
      false -> {:ok, :valid}
    end
  end
  defp validate_message_length(text) when is_binary(text) and byte_size(text) == 0 do
    {:ok, :valid}
  end
  defp validate_message_length(_), do: {:ok, :valid}

  defp validate_connection(socket) do
    if Phoenix.LiveView.connected?(socket) do
      {:ok, :valid}
    else
      {:error, "Conexão perdida. Tente recarregar a página."}
    end
  end

  defp validate_treaty_status(%{assigns: %{treaty: %{status: "closed"}}}) do
    {:error, "Esta tratativa está encerrada. Não é possível enviar mensagens."}
  end
  defp validate_treaty_status(_socket) do
    {:ok, :valid}
  end

  defp process_upload_entry(%{path: path}, entry) do
    temp_path = create_temp_file(path, entry.client_name)

    {:ok, %{
      temp_path: temp_path,
      original_filename: entry.client_name,
      file_size: entry.client_size,
      mime_type: entry.client_type,
      pending_upload: true
    }}
  end

  defp create_temp_file(source_path, original_name) do
    temp_dir = Path.join(System.tmp_dir(), ChatConfig.get_config_value(:upload, :temp_dir_prefix))
    File.mkdir_p!(temp_dir)

    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    unique_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    extension = Path.extname(original_name)
    temp_filename = "upload_#{timestamp}_#{unique_id}#{extension}"
    temp_path = Path.join(temp_dir, temp_filename)

    case File.cp(source_path, temp_path) do
      :ok -> temp_path
      {:error, _reason} ->
        source_path
    end
  end

  defp safe_mark_message_as_read(message_id, user_id, treaty_id) do
    try do
      Chat.mark_message_as_read(message_id, user_id, treaty_id)
    rescue
      _ -> :ok
    end
  end

  defp consume_uploaded_entries(socket, upload_type, callback) do
    Phoenix.LiveView.consume_uploaded_entries(socket, upload_type, callback)
  end
end
