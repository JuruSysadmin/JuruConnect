defmodule AppWeb.Auth.GuardianSessionPlugTest do
  use AppWeb.ConnCase, async: true

  alias AppWeb.Auth.GuardianSessionPlug

  describe "call/2" do
    test "allows requests with no token", %{conn: conn} do
      conn = GuardianSessionPlug.call(conn, [])

      refute conn.halted
      assert get_session(conn, "guardian_default_token") == nil
    end

    test "allows requests with valid JWT format", %{conn: conn} do
      valid_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

      conn =
        conn
        |> put_session("guardian_default_token", valid_token)
        |> GuardianSessionPlug.call([])

      refute conn.halted
      assert get_session(conn, "guardian_default_token") == valid_token
    end

    test "clears malformed tokens from session", %{conn: conn} do
      malformed_token = "malformed.token.here"

      conn =
        conn
        |> put_session("guardian_default_token", malformed_token)
        |> GuardianSessionPlug.call([])

      refute conn.halted
      assert get_session(conn, "guardian_default_token") == nil
      assert conn.assigns.current_user == nil
    end

    test "clears invalid tokens from session", %{conn: conn} do
      invalid_token = "invalid_token"

      conn =
        conn
        |> put_session("guardian_default_token", invalid_token)
        |> GuardianSessionPlug.call([])

      refute conn.halted
      assert get_session(conn, "guardian_default_token") == nil
      assert conn.assigns.current_user == nil
    end

    test "clears non-string tokens from session", %{conn: conn} do
      non_string_token = 12_345

      conn =
        conn
        |> put_session("guardian_default_token", non_string_token)
        |> GuardianSessionPlug.call([])

      refute conn.halted
      assert get_session(conn, "guardian_default_token") == nil
      assert conn.assigns.current_user == nil
    end
  end
end
