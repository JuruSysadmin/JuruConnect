defmodule AppWeb.Layouts do
  @moduledoc """
  Este módulo contém diferentes layouts usados pela aplicação.

  Veja o diretório `layouts` para todos os templates disponíveis.
  O layout "root" é um esqueleto renderizado como parte do
  roteador da aplicação. O layout "app" é definido como layout
  padrão tanto em `use AppWeb, :controller` quanto em
  `use AppWeb, :live_view`.
  """
  use AppWeb, :html

  embed_templates "layouts/*"

  @doc """
  Guard para verificar se um valor é uma string válida (não vazia).
  """
  defguard valid_string?(value) when is_binary(value) and value != ""

  @doc """
  Extrai o nome para exibição do usuário usando pattern matching assertivo.

  Prioriza :name sobre :username para chaves de átomo.
  Retorna "Usuário" como fallback para casos não cobertos.
  """
  def get_user_display_name(%{name: name}) when valid_string?(name), do: name
  def get_user_display_name(%{username: username}) when valid_string?(username), do: username
  def get_user_display_name(%{"name" => name}) when valid_string?(name), do: name
  def get_user_display_name(%{"username" => username}) when valid_string?(username), do: username
  def get_user_display_name(name) when valid_string?(name), do: name
  def get_user_display_name(_), do: "Usuário"

  @doc """
  Extrai o papel/função do usuário usando pattern matching assertivo.

  Retorna nil para casos onde o papel não está definido ou é inválido.
  """
  def get_user_role(%{role: role}) when valid_string?(role), do: role
  def get_user_role(%{"role" => role}) when valid_string?(role), do: role
  def get_user_role(_), do: nil
end
