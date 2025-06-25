defmodule AppWeb.UserSessionLiveTest do
  use AppWeb.ConnCase

  import Phoenix.LiveViewTest
  import App.AuthFixtures

  @create_attrs %{}
  @update_attrs %{}
  @invalid_attrs %{}

  defp create_user_session(_) do
    user_session = user_session_fixture()
    %{user_session: user_session}
  end

  describe "Index" do
    setup [:create_user_session]

    test "lists all user_sessions", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/user_sessions")

      assert html =~ "Listing User sessions"
    end

    test "saves new user_session", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/user_sessions")

      assert index_live |> element("a", "New User session") |> render_click() =~
               "New User session"

      assert_patch(index_live, ~p"/user_sessions/new")

      assert index_live
             |> form("#user_session-form", user_session: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#user_session-form", user_session: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/user_sessions")

      html = render(index_live)
      assert html =~ "User session created successfully"
    end

    test "updates user_session in listing", %{conn: conn, user_session: user_session} do
      {:ok, index_live, _html} = live(conn, ~p"/user_sessions")

      assert index_live
             |> element("#user_sessions-#{user_session.id} a", "Edit")
             |> render_click() =~
               "Edit User session"

      assert_patch(index_live, ~p"/user_sessions/#{user_session}/edit")

      assert index_live
             |> form("#user_session-form", user_session: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#user_session-form", user_session: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/user_sessions")

      html = render(index_live)
      assert html =~ "User session updated successfully"
    end

    test "deletes user_session in listing", %{conn: conn, user_session: user_session} do
      {:ok, index_live, _html} = live(conn, ~p"/user_sessions")

      assert index_live
             |> element("#user_sessions-#{user_session.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#user_sessions-#{user_session.id}")
    end
  end

  describe "Show" do
    setup [:create_user_session]

    test "displays user_session", %{conn: conn, user_session: user_session} do
      {:ok, _show_live, html} = live(conn, ~p"/user_sessions/#{user_session}")

      assert html =~ "Show User session"
    end

    test "updates user_session within modal", %{conn: conn, user_session: user_session} do
      {:ok, show_live, _html} = live(conn, ~p"/user_sessions/#{user_session}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit User session"

      assert_patch(show_live, ~p"/user_sessions/#{user_session}/show/edit")

      assert show_live
             |> form("#user_session-form", user_session: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#user_session-form", user_session: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/user_sessions/#{user_session}")

      html = render(show_live)
      assert html =~ "User session updated successfully"
    end
  end
end
