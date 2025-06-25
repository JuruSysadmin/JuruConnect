defmodule App.AuthTest do
  use App.DataCase

  alias App.Auth

  describe "user_sessions" do
    alias App.Auth.UserSession

    import App.AuthFixtures

    @invalid_attrs %{}

    test "list_user_sessions/0 returns all user_sessions" do
      user_session = user_session_fixture()
      assert Auth.list_user_sessions() == [user_session]
    end

    test "get_user_session!/1 returns the user_session with given id" do
      user_session = user_session_fixture()
      assert Auth.get_user_session!(user_session.id) == user_session
    end

    test "create_user_session/1 with valid data creates a user_session" do
      valid_attrs = %{}

      assert {:ok, %UserSession{} = user_session} = Auth.create_user_session(valid_attrs)
    end

    test "create_user_session/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Auth.create_user_session(@invalid_attrs)
    end

    test "update_user_session/2 with valid data updates the user_session" do
      user_session = user_session_fixture()
      update_attrs = %{}

      assert {:ok, %UserSession{} = user_session} =
               Auth.update_user_session(user_session, update_attrs)
    end

    test "update_user_session/2 with invalid data returns error changeset" do
      user_session = user_session_fixture()
      assert {:error, %Ecto.Changeset{}} = Auth.update_user_session(user_session, @invalid_attrs)
      assert user_session == Auth.get_user_session!(user_session.id)
    end

    test "delete_user_session/1 deletes the user_session" do
      user_session = user_session_fixture()
      assert {:ok, %UserSession{}} = Auth.delete_user_session(user_session)
      assert_raise Ecto.NoResultsError, fn -> Auth.get_user_session!(user_session.id) end
    end

    test "change_user_session/1 returns a user_session changeset" do
      user_session = user_session_fixture()
      assert %Ecto.Changeset{} = Auth.change_user_session(user_session)
    end
  end
end
