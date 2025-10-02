defmodule App.Themes.UserTheme do
  @moduledoc """
  Schema para temas personalizados de usuários.

  Permite que cada usuário customize:
  - Modo claro/escuro
  - Cores personalizadas
  - Papel de parede
  - Tipografia
  - Layout e densidade
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, only: [
    :id, :user_id, :theme_mode, :primary_color, :secondary_color, :accent_color,
    :background_type, :background_color, :background_gradient, :wallpaper_url,
    :wallpaper_opacity, :font_family, :font_size, :border_radius, :animation_speed,
    :compact_mode, :sidebar_collapsed, :message_density, :inserted_at, :updated_at
  ]}

  schema "user_themes" do
    field :user_id, :binary_id
    field :theme_mode, :string, default: "light"
    field :primary_color, :string, default: "#3B82F6"
    field :secondary_color, :string, default: "#10B981"
    field :accent_color, :string, default: "#F59E0B"
    field :background_type, :string, default: "gradient"
    field :background_color, :string, default: "#FFFFFF"
    field :background_gradient, :string
    field :wallpaper_url, :string
    field :wallpaper_opacity, :float, default: 0.1
    field :font_family, :string, default: "Inter"
    field :font_size, :string, default: "medium"
    field :border_radius, :string, default: "medium"
    field :animation_speed, :string, default: "normal"
    field :compact_mode, :boolean, default: false
    field :sidebar_collapsed, :boolean, default: false
    field :message_density, :string, default: "comfortable"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for user theme.
  """
  def changeset(theme, attrs) do
    theme
    |> cast(attrs, [
      :user_id, :theme_mode, :primary_color, :secondary_color, :accent_color,
      :background_type, :background_color, :background_gradient, :wallpaper_url,
      :wallpaper_opacity, :font_family, :font_size, :border_radius, :animation_speed,
      :compact_mode, :sidebar_collapsed, :message_density
    ])
    |> validate_required([:user_id])
    |> validate_inclusion(:theme_mode, ["light", "dark", "auto"])
    |> validate_inclusion(:background_type, ["gradient", "solid", "image"])
    |> validate_inclusion(:font_size, ["small", "medium", "large"])
    |> validate_inclusion(:border_radius, ["none", "small", "medium", "large"])
    |> validate_inclusion(:animation_speed, ["slow", "normal", "fast"])
    |> validate_inclusion(:message_density, ["compact", "comfortable", "spacious"])
    |> validate_number(:wallpaper_opacity, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_format(:primary_color, ~r/^#[0-9A-Fa-f]{6}$/, message: "deve ser uma cor hexadecimal válida")
    |> validate_format(:secondary_color, ~r/^#[0-9A-Fa-f]{6}$/, message: "deve ser uma cor hexadecimal válida")
    |> validate_format(:accent_color, ~r/^#[0-9A-Fa-f]{6}$/, message: "deve ser uma cor hexadecimal válida")
    |> validate_format(:background_color, ~r/^#[0-9A-Fa-f]{6}$/, message: "deve ser uma cor hexadecimal válida")
    |> unique_constraint(:user_id)
  end

  @doc """
  Creates a changeset for theme update.
  """
  def update_changeset(theme, attrs) do
    theme
    |> cast(attrs, [
      :theme_mode, :primary_color, :secondary_color, :accent_color,
      :background_type, :background_color, :background_gradient, :wallpaper_url,
      :wallpaper_opacity, :font_family, :font_size, :border_radius, :animation_speed,
      :compact_mode, :sidebar_collapsed, :message_density
    ])
    |> validate_inclusion(:theme_mode, ["light", "dark", "auto"])
    |> validate_inclusion(:background_type, ["gradient", "solid", "image"])
    |> validate_inclusion(:font_size, ["small", "medium", "large"])
    |> validate_inclusion(:border_radius, ["none", "small", "medium", "large"])
    |> validate_inclusion(:animation_speed, ["slow", "normal", "fast"])
    |> validate_inclusion(:message_density, ["compact", "comfortable", "spacious"])
    |> validate_number(:wallpaper_opacity, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_format(:primary_color, ~r/^#[0-9A-Fa-f]{6}$/, message: "deve ser uma cor hexadecimal válida")
    |> validate_format(:secondary_color, ~r/^#[0-9A-Fa-f]{6}$/, message: "deve ser uma cor hexadecimal válida")
    |> validate_format(:accent_color, ~r/^#[0-9A-Fa-f]{6}$/, message: "deve ser uma cor hexadecimal válida")
    |> validate_format(:background_color, ~r/^#[0-9A-Fa-f]{6}$/, message: "deve ser uma cor hexadecimal válida")
  end

  @doc """
  Returns default theme for a user.
  """
  def default_theme(user_id) do
    %__MODULE__{
      user_id: user_id,
      theme_mode: "light",
      primary_color: "#3B82F6",
      secondary_color: "#10B981",
      accent_color: "#F59E0B",
      background_type: "gradient",
      background_color: "#FFFFFF",
      background_gradient: "linear-gradient(135deg, #667eea 0%, #764ba2 100%)",
      wallpaper_url: nil,
      wallpaper_opacity: 0.1,
      font_family: "Inter",
      font_size: "medium",
      border_radius: "medium",
      animation_speed: "normal",
      compact_mode: false,
      sidebar_collapsed: false,
      message_density: "comfortable"
    }
  end
end
