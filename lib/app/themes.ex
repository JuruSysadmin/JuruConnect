defmodule App.Themes do
  @moduledoc """
  Contexto para gerenciar temas de usuários.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Themes.UserTheme

  @doc """
  Obtém o tema de um usuário ou cria um padrão se não existir.
  """
  def get_user_theme(user_id) when is_binary(user_id) do
    case Repo.get_by(UserTheme, user_id: user_id) do
      nil ->
        # Criar tema padrão
        create_user_theme(%{user_id: user_id})
      theme ->
        {:ok, theme}
    end
  end

  @doc """
  Cria um novo tema para um usuário.
  """
  def create_user_theme(attrs \\ %{}) do
    %UserTheme{}
    |> UserTheme.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Atualiza o tema de um usuário.
  """
  def update_user_theme(%UserTheme{} = theme, attrs) do
    theme
    |> UserTheme.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Atualiza ou cria o tema de um usuário.
  """
  def upsert_user_theme(user_id, attrs) when is_binary(user_id) do
    case get_user_theme(user_id) do
      {:ok, theme} ->
        update_user_theme(theme, attrs)
      {:error, :not_found} ->
        create_user_theme(Map.put(attrs, :user_id, user_id))
    end
  end

  @doc """
  Aplica um tema padrão.
  """
  def apply_preset_theme(user_id, preset_name) when is_binary(user_id) do
    preset_attrs = get_preset_theme(preset_name)
    upsert_user_theme(user_id, preset_attrs)
  end

  @doc """
  Obtém temas pré-definidos.
  """
  def get_preset_theme("light") do
    %{
      theme_mode: "light",
      primary_color: "#3B82F6",
      secondary_color: "#10B981",
      accent_color: "#F59E0B",
      background_type: "gradient",
      background_color: "#FFFFFF",
      background_gradient: "linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%)",
      font_family: "Inter",
      font_size: "medium",
      border_radius: "medium",
      animation_speed: "normal",
      compact_mode: false,
      message_density: "comfortable"
    }
  end

  def get_preset_theme("dark") do
    %{
      theme_mode: "dark",
      primary_color: "#60A5FA",
      secondary_color: "#34D399",
      accent_color: "#FBBF24",
      background_type: "gradient",
      background_color: "#1F2937",
      background_gradient: "linear-gradient(135deg, #667eea 0%, #764ba2 100%)",
      font_family: "Inter",
      font_size: "medium",
      border_radius: "medium",
      animation_speed: "normal",
      compact_mode: false,
      message_density: "comfortable"
    }
  end

  def get_preset_theme("ocean") do
    %{
      theme_mode: "light",
      primary_color: "#0EA5E9",
      secondary_color: "#06B6D4",
      accent_color: "#8B5CF6",
      background_type: "gradient",
      background_color: "#F0F9FF",
      background_gradient: "linear-gradient(135deg, #74b9ff 0%, #0984e3 100%)",
      font_family: "Inter",
      font_size: "medium",
      border_radius: "large",
      animation_speed: "normal",
      compact_mode: false,
      message_density: "comfortable"
    }
  end

  def get_preset_theme("sunset") do
    %{
      theme_mode: "light",
      primary_color: "#F97316",
      secondary_color: "#EF4444",
      accent_color: "#F59E0B",
      background_type: "gradient",
      background_color: "#FFF7ED",
      background_gradient: "linear-gradient(135deg, #ff9a9e 0%, #fecfef 50%, #fecfef 100%)",
      font_family: "Inter",
      font_size: "medium",
      border_radius: "medium",
      animation_speed: "normal",
      compact_mode: false,
      message_density: "comfortable"
    }
  end

  def get_preset_theme("forest") do
    %{
      theme_mode: "light",
      primary_color: "#059669",
      secondary_color: "#10B981",
      accent_color: "#84CC16",
      background_type: "gradient",
      background_color: "#F0FDF4",
      background_gradient: "linear-gradient(135deg, #a8edea 0%, #fed6e3 100%)",
      font_family: "Inter",
      font_size: "medium",
      border_radius: "medium",
      animation_speed: "normal",
      compact_mode: false,
      message_density: "comfortable"
    }
  end

  def get_preset_theme("minimal") do
    %{
      theme_mode: "light",
      primary_color: "#374151",
      secondary_color: "#6B7280",
      accent_color: "#9CA3AF",
      background_type: "solid",
      background_color: "#FFFFFF",
      background_gradient: nil,
      font_family: "Inter",
      font_size: "medium",
      border_radius: "small",
      animation_speed: "fast",
      compact_mode: true,
      message_density: "compact"
    }
  end

  def get_preset_theme(_), do: get_preset_theme("light")

  @doc """
  Lista todos os temas pré-definidos disponíveis.
  """
  def list_preset_themes do
    [
      %{name: "light", label: "Claro", description: "Tema claro padrão"},
      %{name: "dark", label: "Escuro", description: "Tema escuro para uso noturno"},
      %{name: "ocean", label: "Oceano", description: "Tema azul inspirado no oceano"},
      %{name: "sunset", label: "Pôr do Sol", description: "Tema quente com cores do entardecer"},
      %{name: "forest", label: "Floresta", description: "Tema verde inspirado na natureza"},
      %{name: "minimal", label: "Minimalista", description: "Tema limpo e minimalista"}
    ]
  end

  @doc """
  Gera CSS customizado baseado no tema do usuário.
  """
  def generate_custom_css(%UserTheme{} = theme) do
    """
    :root {
      --primary-color: #{theme.primary_color};
      --secondary-color: #{theme.secondary_color};
      --accent-color: #{theme.accent_color};
      --background-color: #{theme.background_color};
      --font-family: #{theme.font_family}, system-ui, -apple-system, sans-serif;
      --border-radius: #{get_border_radius_value(theme.border_radius)};
      --animation-speed: #{get_animation_speed_value(theme.animation_speed)};
      --message-density: #{get_message_density_value(theme.message_density)};
    }

    .theme-background {
      #{get_background_css(theme)}
    }

    .theme-text {
      color: #{get_text_color(theme)};
    }

    .theme-primary {
      background-color: #{theme.primary_color};
      color: white;
    }

    .theme-secondary {
      background-color: #{theme.secondary_color};
      color: white;
    }

    .theme-accent {
      background-color: #{theme.accent_color};
      color: white;
    }
    """
  end

  defp get_border_radius_value("none"), do: "0px"
  defp get_border_radius_value("small"), do: "4px"
  defp get_border_radius_value("medium"), do: "8px"
  defp get_border_radius_value("large"), do: "16px"

  defp get_animation_speed_value("slow"), do: "0.5s"
  defp get_animation_speed_value("normal"), do: "0.3s"
  defp get_animation_speed_value("fast"), do: "0.1s"

  defp get_message_density_value("compact"), do: "0.5rem"
  defp get_message_density_value("comfortable"), do: "1rem"
  defp get_message_density_value("spacious"), do: "1.5rem"

  defp get_background_css(%UserTheme{background_type: "solid"} = theme) do
    "background-color: #{theme.background_color};"
  end

  defp get_background_css(%UserTheme{background_type: "gradient"} = theme) do
    gradient = theme.background_gradient || "linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%)"
    "background: #{gradient};"
  end

  defp get_background_css(%UserTheme{background_type: "image", wallpaper_url: url} = theme) when not is_nil(url) do
    """
    background-image: url('#{url}');
    background-size: cover;
    background-position: center;
    background-repeat: no-repeat;
    background-color: #{theme.background_color};
    opacity: #{theme.wallpaper_opacity};
    """
  end

  defp get_background_css(_) do
    "background-color: #FFFFFF;"
  end

  defp get_text_color(%UserTheme{theme_mode: "dark"}), do: "#F9FAFB"
  defp get_text_color(_), do: "#111827"
end
