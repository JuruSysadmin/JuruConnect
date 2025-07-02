defmodule AppWeb.Auth.GuardianPlug do
  @moduledoc """
  Guardian Plug functions for authentication in Phoenix controllers.

  Provides convenient functions for signing in, signing out, and managing
  user sessions with JWT tokens.
  """

  alias AppWeb.Auth.Guardian
  import Plug.Conn
  import Phoenix.Controller

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, opts) do
    case opts do
      :load_current_user -> load_current_user(conn, [])
      :ensure_authenticated -> ensure_authenticated(conn, [])
      :require_admin -> require_admin(conn, [])
      :require_manager_or_admin -> require_manager_or_admin(conn, [])
      {:require_role, roles} -> require_role(conn, [roles: roles])
      _ -> conn
    end
  end

  def sign_in(conn, user) do
    Guardian.Plug.sign_in(conn, user)
  end

  def sign_out(conn) do
    Guardian.Plug.sign_out(conn)
  end

  def current_user(conn) do
    Guardian.Plug.current_resource(conn)
  end

  def authenticated?(conn) do
    Guardian.Plug.authenticated?(conn)
  end

  def ensure_authenticated(conn, _opts) do
    if authenticated?(conn) do
      conn
    else
      conn
      |> put_flash(:error, "Você precisa estar logado para acessar esta página.")
      |> redirect(to: "/auth/login")
      |> halt()
    end
  end

  def maybe_current_user(conn, _opts) do
    if authenticated?(conn) do
      conn
      |> assign(:current_user, current_user(conn))
    else
      conn
      |> assign(:current_user, nil)
    end
  end

  def require_admin(conn, _opts) do
    case current_user(conn) do
      %{role: "admin"} -> conn
      _ ->
        conn
        |> put_flash(:error, "Acesso negado. Apenas administradores podem acessar esta página.")
        |> redirect(to: "/dashboard")
        |> halt()
    end
  end

  def require_manager_or_admin(conn, _opts) do
    case current_user(conn) do
      %{role: role} when role in ["admin", "manager"] -> conn
      _ ->
        conn
        |> put_flash(:error, "Acesso negado. Apenas administradores e gerentes podem acessar esta página.")
        |> redirect(to: "/dashboard")
        |> halt()
    end
  end

  def require_role(conn, opts) do
    required_roles = Keyword.get(opts, :roles, [])

    case current_user(conn) do
      %{role: role} ->
        if Enum.member?(required_roles, role) do
          conn
        else
          conn
          |> put_flash(:error, "Acesso negado. Você não tem permissão para acessar esta página.")
          |> redirect(to: "/dashboard")
          |> halt()
        end
      _ ->
        conn
        |> put_flash(:error, "Acesso negado. Você não tem permissão para acessar esta página.")
        |> redirect(to: "/dashboard")
        |> halt()
    end
  end

  def load_current_user(conn, _opts) do
    try do
      case Guardian.Plug.current_resource(conn) do
        nil ->
          conn
          |> assign(:current_user, nil)
        user ->
          conn
          |> assign(:current_user, user)
      end
    rescue
      _ ->
        # Em caso de erro, apenas definir current_user como nil
        conn
        |> assign(:current_user, nil)
    end
  end
end
