defmodule AppWeb.DashboardLiveTest do
  use AppWeb.ConnCase
  import Phoenix.LiveViewTest

  alias App.Accounts
  alias AppWeb.Auth.Guardian

  setup %{conn: conn} do
    store = App.Stores.get_store_by!("Loja Padrão")

    {:ok, user} =
      Accounts.create_user(%{
        username: "testuser",
        name: "Test User",
        password: "123456",
        role: "clerk",
        store_id: store.id
      })

    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    # Simula uma sessão autenticada
    conn = %{
      conn
      | private: Map.put(conn.private, :phoenix_session, %{"guardian_default_token" => token})
    }

    {:ok, conn: conn, user: user}
  end

  test "exibe o nome de usuário na sidebar quando autenticado", %{conn: conn, user: user} do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {:ok, _view, html} = live(conn, "/hello?token=#{token}")
    assert html =~ user.username
  end
end
