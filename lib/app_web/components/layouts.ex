defmodule AppWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use AppWeb, :controller` and
  `use AppWeb, :live_view`.
  """
  use AppWeb, :html

  embed_templates "layouts/*"

  @doc """
  Extrai o nome para exibição do usuário de forma segura.

  Lida com diferentes tipos de dados:
  - Mapa com chaves :name ou :username
  - String simples
  - Nil ou valores inválidos
  """
  def get_user_display_name(user) do
    case user do
      %{name: name} when is_binary(name) and name != "" -> name
      %{username: username} when is_binary(username) and username != "" -> username
      %{"name" => name} when is_binary(name) and name != "" -> name
      %{"username" => username} when is_binary(username) and username != "" -> username
      name when is_binary(name) and name != "" -> name
      _ -> "Usuário"
    end
  end

  @doc """
  Extrai o papel/função do usuário de forma segura.

  Retorna nil se não houver papel definido.
  """
  def get_user_role(user) do
    case user do
      %{role: role} when is_binary(role) and role != "" -> role
      %{"role" => role} when is_binary(role) and role != "" -> role
      _ -> nil
    end
  end
end
