defmodule AppWeb.ThemeSettingsLive do
  @moduledoc """
  LiveView para configurações de tema do usuário.

  Permite que o usuário:
  - Escolha entre temas pré-definidos
  - Personalize cores
  - Faça upload de papel de parede
  - Configure tipografia e layout
  """

  use AppWeb, :live_view
  alias App.Themes
  alias App.Themes.UserTheme

  @impl true
  def mount(_params, session, socket) do
    user = get_user_from_session(session)

    if user do
      {:ok, theme} = Themes.get_user_theme(user.id)

      socket = socket
      |> assign(:user, user)
      |> assign(:theme, theme)
      |> assign(:preset_themes, Themes.list_preset_themes())
      |> assign(:show_color_picker, false)
      |> assign(:show_wallpaper_upload, false)
      |> assign(:uploading_wallpaper, false)
      |> allow_upload(:wallpaper,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 1,
        max_file_size: 10_000_000, # 10MB
        auto_upload: false
      )

      {:ok, socket}
    else
      {:ok, redirect(socket, to: "/login")}
    end
  end

  @impl true
  def handle_event("apply_preset", %{"preset" => preset_name}, socket) do
    case Themes.apply_preset_theme(socket.assigns.user.id, preset_name) do
      {:ok, theme} ->
        socket = socket
        |> assign(:theme, theme)
        |> put_flash(:info, "Tema '#{get_preset_label(preset_name)}' aplicado com sucesso!")

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Erro ao aplicar tema")}
    end
  end

  @impl true
  def handle_event("update_color", %{"field" => field, "color" => color}, socket) do
    attrs = %{field => color}

    case Themes.update_user_theme(socket.assigns.theme, attrs) do
      {:ok, theme} ->
        {:noreply, assign(socket, :theme, theme)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Erro ao atualizar cor")}
    end
  end

  @impl true
  def handle_event("update_setting", %{"field" => field, "value" => value}, socket) do
    attrs = %{field => value}

    case Themes.update_user_theme(socket.assigns.theme, attrs) do
      {:ok, theme} ->
        {:noreply, assign(socket, :theme, theme)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Erro ao atualizar configuração")}
    end
  end

  @impl true
  def handle_event("toggle_color_picker", _params, socket) do
    {:noreply, assign(socket, :show_color_picker, !socket.assigns.show_color_picker)}
  end

  @impl true
  def handle_event("toggle_wallpaper_upload", _params, socket) do
    {:noreply, assign(socket, :show_wallpaper_upload, !socket.assigns.show_wallpaper_upload)}
  end

  @impl true
  def handle_event("upload_wallpaper", _params, socket) do
    if socket.assigns.uploads.wallpaper.entries != [] do
      entry = hd(socket.assigns.uploads.wallpaper.entries)

      if entry.done? do
        consume_uploaded_entries(socket, :wallpaper, fn %{path: path}, entry ->
          # Criar arquivo temporário
          temp_path = create_temp_wallpaper_file(path, entry.client_name)

          # Enviar job para processamento
          job_args = %{
            "file_path" => temp_path,
            "user_id" => socket.assigns.user.id,
            "original_filename" => entry.client_name,
            "file_size" => entry.client_size,
            "mime_type" => entry.client_type
          }

          App.Jobs.WallpaperProcessingJob.new(job_args)
          |> Oban.insert()

          {:ok, :uploaded}
        end)

        socket = socket
        |> assign(:uploading_wallpaper, true)
        |> put_flash(:info, "Papel de parede enviado! Processando...")

        {:noreply, socket}
      else
        {:noreply, put_flash(socket, :error, "Aguarde o upload terminar")}
      end
    else
      {:noreply, put_flash(socket, :error, "Selecione um arquivo primeiro")}
    end
  end

  @impl true
  def handle_event("remove_wallpaper", _params, socket) do
    case Themes.update_user_theme(socket.assigns.theme, %{
      background_type: "gradient",
      wallpaper_url: nil
    }) do
      {:ok, theme} ->
        {:noreply, assign(socket, :theme, theme)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Erro ao remover papel de parede")}
    end
  end

  @impl true
  def handle_info({:wallpaper_applied, %{wallpaper_url: _url}}, socket) do
    # Recarregar tema para obter a URL atualizada
    {:ok, theme} = Themes.get_user_theme(socket.assigns.user.id)

    socket = socket
    |> assign(:theme, theme)
    |> assign(:uploading_wallpaper, false)
    |> put_flash(:info, "Papel de parede aplicado com sucesso!")

    {:noreply, socket}
  end

  # Funções auxiliares

  defp get_user_from_session(session) do
    case session["user_token"] do
      nil -> nil
      token ->
        case AppWeb.Auth.Guardian.resource_from_token(token) do
          {:ok, user, _claims} -> user
          {:error, _reason} -> nil
        end
    end
  end

  defp get_preset_label(preset_name) do
    case preset_name do
      "light" -> "Claro"
      "dark" -> "Escuro"
      "ocean" -> "Oceano"
      "sunset" -> "Pôr do Sol"
      "forest" -> "Floresta"
      "minimal" -> "Minimalista"
      _ -> "Desconhecido"
    end
  end

  defp create_temp_wallpaper_file(source_path, original_name) do
    # Criar diretório temporário se não existir
    temp_dir = Path.join(System.tmp_dir(), "juruconnect_wallpapers")
    File.mkdir_p!(temp_dir)

    # Gerar nome único para arquivo temporário
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    unique_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    extension = Path.extname(original_name)
    temp_filename = "wallpaper_#{timestamp}_#{unique_id}#{extension}"
    temp_path = Path.join(temp_dir, temp_filename)

    # Copiar arquivo para local temporário
    case File.cp(source_path, temp_path) do
      :ok -> temp_path
      {:error, _reason} -> source_path
    end
  end
end
