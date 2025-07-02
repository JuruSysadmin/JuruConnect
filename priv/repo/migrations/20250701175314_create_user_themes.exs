defmodule App.Repo.Migrations.CreateUserThemes do
  @moduledoc """
  Cria tabela para armazenar configurações de temas personalizáveis dos usuários.

  Permite que cada usuário customize cores e aparência do chat.
  """

  use Ecto.Migration

  def change do
    create table(:user_themes) do
      add :user_id, :string, null: false
      add :theme_name, :string, default: "default"

      # Cores principais
      add :primary_color, :string, default: "#075E54"     # Verde WhatsApp
      add :secondary_color, :string, default: "#128C7E"   # Verde escuro
      add :accent_color, :string, default: "#DCF8C6"      # Verde claro mensagens

      # Cores de fundo
      add :background_color, :string, default: "#FFFFFF"   # Fundo branco
      add :chat_background, :string, default: "#E5DDD5"    # Fundo chat bege
      add :message_bg_sent, :string, default: "#DCF8C6"    # Mensagens enviadas
      add :message_bg_received, :string, default: "#FFFFFF" # Mensagens recebidas

      # Cores de texto
      add :text_color, :string, default: "#303030"         # Texto principal
      add :text_secondary, :string, default: "#667781"     # Texto secundário

      # Configurações de aparência
      add :font_size, :string, default: "medium"           # small, medium, large
      add :border_radius, :string, default: "rounded"      # none, rounded, full
      add :message_density, :string, default: "normal"     # compact, normal, spacious

      # Configurações avançadas
      add :dark_mode, :boolean, default: false
      add :high_contrast, :boolean, default: false
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime_usec)
    end

    # Índices para performance
    create unique_index(:user_themes, [:user_id])
    create index(:user_themes, [:theme_name])
    create index(:user_themes, [:is_active])
  end
end
