defmodule AppWeb.LiveUserAuth do
  @moduledoc """
  Hook on_mount para carregar o current_user nas LiveViews a partir da sessão Guardian.

  Este módulo garante que todas as LiveViews protegidas tenham acesso ao usuário
  logado através do assign :current_user.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias AppWeb.Auth.Guardian

  def on_mount(:default, _params, session, socket) do
    socket = assign_current_user(socket, session)
    {:cont, socket}
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = assign_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/auth/login")}
    end
  end

  defp assign_current_user(socket, session) do
    case session do
      %{"guardian_default_token" => token} when is_binary(token) ->
        case Guardian.decode_and_verify(token) do
          {:ok, claims} ->
            case Guardian.resource_from_claims(claims) do
              {:ok, user} ->
                assign(socket, :current_user, user)
              _ ->
                assign(socket, :current_user, nil)
            end
          _ ->
            assign(socket, :current_user, nil)
        end
      _ ->
        assign(socket, :current_user, nil)
    end
  end
end
