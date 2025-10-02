defmodule AppWeb.UserAuth do
  @moduledoc """
  Authentication hooks for LiveView components.

  Provides authentication callbacks that can be used with the on_mount macro
  to automatically authenticate users and assign the current_user to socket assigns.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:require_authenticated_user, _params, session, socket) do
    case session["user_token"] do
      nil ->
        {:halt, redirect(socket, to: "/login")}

      token ->
        case AppWeb.Auth.Guardian.resource_from_token(token) do
          {:ok, user, _claims} ->
            # Use assign/3 to assign current_user
            {:cont, assign(socket, :current_user, user)}

          {:error, _reason} ->
            {:halt, redirect(socket, to: "/login")}
        end
    end
  end

  def on_mount(:optional_authenticated_user, _params, session, socket) do
    case session["user_token"] do
      nil ->
        {:cont, socket}

      token ->
        case AppWeb.Auth.Guardian.resource_from_token(token) do
          {:ok, user, _claims} ->
            {:cont, assign(socket, :current_user, user)}

          {:error, _reason} ->
            {:cont, socket}
        end
    end
  end

  def on_mount(:get_current_user_from_session, _params, session, socket) do
    case session["current_user"] do
      nil ->
        {:halt, redirect(socket, to: "/login")}

      user_data ->
        # Convert session data to user struct
        user = struct(App.Accounts.User, user_data)
        {:cont, assign(socket, :current_user, user)}
    end
  end
end
