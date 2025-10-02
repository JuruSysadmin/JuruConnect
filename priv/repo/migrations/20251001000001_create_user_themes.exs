defmodule App.Repo.Migrations.CreateUserThemes do
  use Ecto.Migration

  def change do
    create table(:user_themes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :theme_mode, :string, default: "light", null: false
      add :primary_color, :string, default: "#3B82F6"
      add :secondary_color, :string, default: "#10B981"
      add :accent_color, :string, default: "#F59E0B"
      add :background_type, :string, default: "gradient" # gradient, solid, image
      add :background_color, :string, default: "#FFFFFF"
      add :background_gradient, :text
      add :wallpaper_url, :string
      add :wallpaper_opacity, :float, default: 0.1
      add :font_family, :string, default: "Inter"
      add :font_size, :string, default: "medium" # small, medium, large
      add :border_radius, :string, default: "medium" # none, small, medium, large
      add :animation_speed, :string, default: "normal" # slow, normal, fast
      add :compact_mode, :boolean, default: false
      add :sidebar_collapsed, :boolean, default: false
      add :message_density, :string, default: "comfortable" # compact, comfortable, spacious

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_themes, [:user_id])
    create index(:user_themes, [:theme_mode])
  end
end
