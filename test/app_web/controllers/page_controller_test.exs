defmodule AppWeb.PageControllerTest do
  use AppWeb.ConnCase, async: true

  describe "home page" do
    test "renders home page successfully when no token is present", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200)
    end

    test "renders home page successfully when invalid token is present", %{conn: conn} do
      # Simula um token inválido na sessão (como o que está causando o erro)
      conn =
        conn
        |> fetch_session()
        |> put_session("guardian_default_token", "invalid_token_that_doesnt_exist")
        |> get(~p"/")

      # Should still render successfully, not crash with NotSentError
      assert html_response(conn, 200)
    end

    test "renders home page successfully when expired token is present", %{conn: conn} do
      # Simula um token expirado
      conn =
        conn
        |> fetch_session()
        |> put_session("guardian_default_token", "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.expired")
        |> get(~p"/")

      # Should still render successfully
      assert html_response(conn, 200)
    end

    test "renders home page successfully when valid user is authenticated", %{conn: conn} do
      user = insert(:user)
      conn =
        conn
        |> AppWeb.Auth.GuardianPlug.sign_in(user)
        |> get(~p"/")

      assert html_response(conn, 200)
    end
  end
end
