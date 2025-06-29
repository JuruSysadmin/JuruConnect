defmodule AppWeb.Auth.GuardianPlugTest do
  use AppWeb.ConnCase, async: true

  alias AppWeb.Auth.GuardianPlug
  alias App.Accounts

  describe "ensure_authenticated/2" do
    test "redirects to login when user is not authenticated", %{conn: conn} do
      conn = GuardianPlug.ensure_authenticated(conn, [])

      assert redirected_to(conn) == "/auth/login"
      assert get_flash(conn, :error) == "Você precisa estar logado para acessar esta página."
      assert conn.halted
    end

    test "allows access when user is authenticated", %{conn: conn} do
      user = insert(:user)
      conn =
        conn
        |> GuardianPlug.sign_in(user)
        |> GuardianPlug.ensure_authenticated([])

      refute conn.halted
      refute redirected_to(conn)
    end
  end

  describe "load_current_user/2" do
    test "assigns nil when no user is authenticated", %{conn: conn} do
      conn = GuardianPlug.load_current_user(conn, [])

      assert conn.assigns.current_user == nil
    end

    test "assigns current user when authenticated", %{conn: conn} do
      user = insert(:user)
      conn =
        conn
        |> GuardianPlug.sign_in(user)
        |> GuardianPlug.load_current_user([])

      assert conn.assigns.current_user.id == user.id
    end

    test "handles errors gracefully when token is invalid", %{conn: conn} do
      # Simulate an invalid token scenario
      conn =
        conn
        |> put_session("guardian_default_token", "invalid_token")
        |> GuardianPlug.load_current_user([])

      assert conn.assigns.current_user == nil
    end
  end

  describe "require_admin/2" do
    test "allows access for admin users", %{conn: conn} do
      admin = insert(:user, role: "admin")
      conn =
        conn
        |> GuardianPlug.sign_in(admin)
        |> GuardianPlug.require_admin([])

      refute conn.halted
    end

    test "redirects non-admin users", %{conn: conn} do
      user = insert(:user, role: "user")
      conn =
        conn
        |> GuardianPlug.sign_in(user)
        |> GuardianPlug.require_admin([])

      assert redirected_to(conn) == "/dashboard"
      assert get_flash(conn, :error) == "Acesso negado. Apenas administradores podem acessar esta página."
      assert conn.halted
    end
  end

  describe "require_manager_or_admin/2" do
    test "allows access for admin users", %{conn: conn} do
      admin = insert(:user, role: "admin")
      conn =
        conn
        |> GuardianPlug.sign_in(admin)
        |> GuardianPlug.require_manager_or_admin([])

      refute conn.halted
    end

    test "allows access for manager users", %{conn: conn} do
      manager = insert(:user, role: "manager")
      conn =
        conn
        |> GuardianPlug.sign_in(manager)
        |> GuardianPlug.require_manager_or_admin([])

      refute conn.halted
    end

    test "redirects regular users", %{conn: conn} do
      user = insert(:user, role: "user")
      conn =
        conn
        |> GuardianPlug.sign_in(user)
        |> GuardianPlug.require_manager_or_admin([])

      assert redirected_to(conn) == "/dashboard"
      assert get_flash(conn, :error) == "Acesso negado. Apenas administradores e gerentes podem acessar esta página."
      assert conn.halted
    end
  end
end
