defmodule App.UserTheme do
  @moduledoc """
  Schema para configurações de temas personalizáveis dos usuários.
  Desenvolvido seguindo TDD com documentação completa em português.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "user_themes" do
    field :user_id, :string
    field :theme_name, :string, default: "default"
    field :primary_color, :string, default: "#075E54"
    field :secondary_color, :string, default: "#128C7E"
    field :accent_color, :string, default: "#DCF8C6"
    field :background_color, :string, default: "#FFFFFF"
    field :chat_background, :string, default: "#E5DDD5"
    field :message_bg_sent, :string, default: "#DCF8C6"
    field :message_bg_received, :string, default: "#FFFFFF"
    field :text_color, :string, default: "#303030"
    field :text_secondary, :string, default: "#667781"
    field :font_size, :string, default: "medium"
    field :border_radius, :string, default: "rounded"
    field :message_density, :string, default: "normal"
    field :dark_mode, :boolean, default: false
    field :high_contrast, :boolean, default: false
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user_theme, attrs) do
    user_theme
    |> cast(attrs, [
      :user_id, :theme_name, :primary_color, :secondary_color, :accent_color,
      :background_color, :chat_background, :message_bg_sent, :message_bg_received,
      :text_color, :text_secondary, :font_size, :border_radius, :message_density,
      :dark_mode, :high_contrast, :is_active
    ])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end
end
