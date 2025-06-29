defmodule AppWeb.Auth.GuardianErrorHandlerTest do
  use AppWeb.ConnCase, async: true

  alias AppWeb.Auth.GuardianErrorHandler

  describe "auth_error/3" do
    test "handles invalid token error on public route without redirecting", %{conn: conn} do
      conn =
        conn
        |> Map.put(:request_path, "/")
        |> GuardianErrorHandler.auth_error({:invalid_token, :token_not_found}, [])

      # Should not be halted on public routes
      refute conn.halted
      assert conn.status != 302
    end

    test "handles invalid token error on protected route without redirecting", %{conn: conn} do
      conn =
        conn
        |> Map.put(:request_path, "/dashboard")
        |> GuardianErrorHandler.auth_error({:invalid_token, :token_not_found}, [])

      # Should not be halted in error handler - the :auth pipeline will handle it
      refute conn.halted
      assert conn.status != 302
    end

    test "handles authentication error on login page", %{conn: conn} do
      conn =
        conn
        |> Map.put(:request_path, "/auth/login")
        |> GuardianErrorHandler.auth_error({:invalid_token, :token_not_found}, [])

      # Should not be halted on login page
      refute conn.halted
      assert conn.status != 302
    end

    test "handles unauthenticated error gracefully", %{conn: conn} do
      conn =
        conn
        |> Map.put(:request_path, "/")
        |> GuardianErrorHandler.auth_error({:unauthenticated, :unauthenticated}, [])

      # Should not be halted on public routes
      refute conn.halted
      assert conn.status != 302
    end
  end
end
