defmodule App.UserThemeTest do
  @moduledoc """
  Testes para o sistema de temas personalizáveis dos usuários.

  Testa funcionalidades de:
  - Criação e atualização de temas
  - Validação de cores hexadecimais
  - Configurações de aparência (fonte, bordas, densidade)
  - Aplicação de temas no chat
  - Modo escuro e alto contraste

  Desenvolvido seguindo TDD com documentação completa em português.
  """

  use App.DataCase, async: true

  alias App.UserTheme
  alias App.Theme

  @valid_theme_attrs %{
    user_id: "user123",
    theme_name: "tema_personalizado",
    primary_color: "#075E54",
    secondary_color: "#128C7E",
    accent_color: "#DCF8C6",
    background_color: "#FFFFFF",
    chat_background: "#E5DDD5",
    message_bg_sent: "#DCF8C6",
    message_bg_received: "#FFFFFF",
    text_color: "#303030",
    text_secondary: "#667781",
    font_size: "medium",
    border_radius: "rounded",
    message_density: "normal",
    dark_mode: false,
    high_contrast: false,
    is_active: true
  }

  describe "changeset/2" do
    test "cria changeset válido com atributos corretos" do
      changeset = UserTheme.changeset(%UserTheme{}, @valid_theme_attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :user_id) == "user123"
      assert Ecto.Changeset.get_change(changeset, :primary_color) == "#075E54"
    end

    test "valida presença de user_id obrigatório" do
      attrs = Map.delete(@valid_theme_attrs, :user_id)
      changeset = UserTheme.changeset(%UserTheme{}, attrs)

      refute changeset.valid?
      assert {:user_id, ["can't be blank"]} in changeset.errors
    end

    test "valida formato hexadecimal das cores" do
      invalid_attrs = %{@valid_theme_attrs | primary_color: "não-é-cor"}
      changeset = UserTheme.changeset(%UserTheme{}, invalid_attrs)

      refute changeset.valid?
      assert {:primary_color, ["deve ser uma cor hexadecimal válida"]} in changeset.errors
    end

    test "aceita cores hexadecimais válidas com 3 e 6 dígitos" do
      # Cor com 3 dígitos
      attrs_3 = %{@valid_theme_attrs | primary_color: "#FFF"}
      changeset_3 = UserTheme.changeset(%UserTheme{}, attrs_3)
      assert changeset_3.valid?

      # Cor com 6 dígitos
      attrs_6 = %{@valid_theme_attrs | primary_color: "#FFFFFF"}
      changeset_6 = UserTheme.changeset(%UserTheme{}, attrs_6)
      assert changeset_6.valid?
    end

    test "valida valores de font_size permitidos" do
      valid_sizes = ["small", "medium", "large"]

      for size <- valid_sizes do
        attrs = %{@valid_theme_attrs | font_size: size}
        changeset = UserTheme.changeset(%UserTheme{}, attrs)
        assert changeset.valid?, "#{size} deveria ser válido"
      end

      invalid_attrs = %{@valid_theme_attrs | font_size: "gigante"}
      changeset = UserTheme.changeset(%UserTheme{}, invalid_attrs)
      refute changeset.valid?
    end

    test "valida valores de border_radius permitidos" do
      valid_radii = ["none", "rounded", "full"]

      for radius <- valid_radii do
        attrs = %{@valid_theme_attrs | border_radius: radius}
        changeset = UserTheme.changeset(%UserTheme{}, attrs)
        assert changeset.valid?, "#{radius} deveria ser válido"
      end
    end

    test "valida valores de message_density permitidos" do
      valid_densities = ["compact", "normal", "spacious"]

      for density <- valid_densities do
        attrs = %{@valid_theme_attrs | message_density: density}
        changeset = UserTheme.changeset(%UserTheme{}, attrs)
        assert changeset.valid?, "#{density} deveria ser válido"
      end
    end
  end

  describe "Theme.get_user_theme/1" do
    test "retorna tema do usuário quando existe" do
      {:ok, theme} = UserTheme.changeset(%UserTheme{}, @valid_theme_attrs)
                     |> Repo.insert()

      assert retrieved_theme = Theme.get_user_theme("user123")
      assert retrieved_theme.user_id == "user123"
      assert retrieved_theme.primary_color == "#075E54"
    end

    test "retorna tema padrão quando usuário não tem tema" do
      default_theme = Theme.get_user_theme("user_sem_tema")

      assert default_theme.theme_name == "default"
      assert default_theme.primary_color == "#075E54"
      assert default_theme.dark_mode == false
    end
  end

  describe "Theme.create_or_update_theme/2" do
    test "cria novo tema para usuário" do
      assert {:ok, theme} = Theme.create_or_update_theme("user456", @valid_theme_attrs)

      assert theme.user_id == "user456"
      assert theme.primary_color == "#075E54"
    end

    test "atualiza tema existente do usuário" do
      # Criar tema inicial
      {:ok, _initial} = Theme.create_or_update_theme("user789", @valid_theme_attrs)

      # Atualizar com novas cores
      updated_attrs = %{@valid_theme_attrs | primary_color: "#FF5722"}
      assert {:ok, updated_theme} = Theme.create_or_update_theme("user789", updated_attrs)

      assert updated_theme.primary_color == "#FF5722"

      # Verificar que só existe um tema para o usuário
      themes = Repo.all(UserTheme) |> Enum.filter(&(&1.user_id == "user789"))
      assert length(themes) == 1
    end
  end

  describe "Theme.apply_dark_mode/2" do
    test "aplica cores de modo escuro quando habilitado" do
      light_theme = %{@valid_theme_attrs | dark_mode: false}
      {:ok, theme} = Theme.create_or_update_theme("user_dark", light_theme)

      dark_theme = Theme.apply_dark_mode(theme, true)

      assert dark_theme.dark_mode == true
      assert dark_theme.background_color == "#1F1F1F"
      assert dark_theme.chat_background == "#0B0B0B"
      assert dark_theme.text_color == "#E1E1E1"
    end

    test "restaura cores originais quando modo escuro desabilitado" do
      dark_attrs = %{@valid_theme_attrs | dark_mode: true, background_color: "#1F1F1F"}
      {:ok, theme} = Theme.create_or_update_theme("user_light", dark_attrs)

      light_theme = Theme.apply_dark_mode(theme, false)

      assert light_theme.dark_mode == false
      assert light_theme.background_color == "#FFFFFF"
      assert light_theme.chat_background == "#E5DDD5"
    end
  end

  describe "Theme.generate_css/1" do
    test "gera CSS válido a partir do tema" do
      {:ok, theme} = Theme.create_or_update_theme("user_css", @valid_theme_attrs)

      css = Theme.generate_css(theme)

      assert String.contains?(css, "--primary-color: #075E54")
      assert String.contains?(css, "--secondary-color: #128C7E")
      assert String.contains?(css, "--background-color: #FFFFFF")
      assert String.contains?(css, "font-size: medium")
      assert String.contains?(css, "border-radius: 12px") # "rounded" -> 12px
    end

    test "gera CSS com classes de densidade de mensagens" do
      compact_attrs = %{@valid_theme_attrs | message_density: "compact"}
      {:ok, theme} = Theme.create_or_update_theme("user_compact", compact_attrs)

      css = Theme.generate_css(theme)

      assert String.contains?(css, ".message { margin: 2px")
      assert String.contains?(css, "padding: 4px")
    end

    test "gera CSS com configurações de fonte" do
      large_font_attrs = %{@valid_theme_attrs | font_size: "large"}
      {:ok, theme} = Theme.create_or_update_theme("user_large", large_font_attrs)

      css = Theme.generate_css(theme)

      assert String.contains?(css, "font-size: 1.125rem") # large = 1.125rem
    end
  end

  describe "Theme.validate_color/1" do
    test "valida cores hexadecimais corretas" do
      valid_colors = ["#FFF", "#FFFFFF", "#123", "#abc123", "#ABC123"]

      for color <- valid_colors do
        assert Theme.validate_color(color) == :ok, "#{color} deveria ser válida"
      end
    end

    test "rejeita cores inválidas" do
      invalid_colors = ["não-cor", "#GGG", "#12345", "#1234567", "rgb(255,0,0)", ""]

      for color <- invalid_colors do
        assert Theme.validate_color(color) == {:error, :invalid_color}, "#{color} deveria ser inválida"
      end
    end
  end

  describe "Theme.preset_themes/0" do
    test "retorna temas predefinidos disponíveis" do
      presets = Theme.preset_themes()

      assert is_list(presets)
      assert length(presets) > 0

      # Verificar que tem pelo menos o tema padrão WhatsApp
      whatsapp_theme = Enum.find(presets, &(&1.theme_name == "whatsapp"))
      assert whatsapp_theme != nil
      assert whatsapp_theme.primary_color == "#075E54"
    end

    test "temas predefinidos têm todas as cores necessárias" do
      presets = Theme.preset_themes()

      for preset <- presets do
        assert is_binary(preset.primary_color)
        assert is_binary(preset.secondary_color)
        assert is_binary(preset.background_color)
        assert is_binary(preset.text_color)
        assert is_boolean(preset.dark_mode)
      end
    end
  end
end
