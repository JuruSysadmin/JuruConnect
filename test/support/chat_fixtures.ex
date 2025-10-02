defmodule App.ChatFixtures do
  @moduledoc """
  This module defines test fixtures for chat-related tests
  """

  alias App.Accounts.User
  alias App.Treaties.Treaty

  def user_fixture(attrs \\ %{}) do
    default_attrs = %{
      name: "Test User",
      username: "test_user",
      email: "test@example.com"
    }

    attrs = Enum.into(attrs, default_attrs)

    {:ok, user} =
      %User{}
      |> User.registration_changeset(attrs)
      |> App.Repo.insert()

    user
  end

  def treaty_fixture(attrs \\ %{}) do
    default_attrs = %{
      treaty_code: "TEST-#{:rand.uniform(9999)}",
      name: "Test Treaty",
      status: "active"
    }

    attrs = Enum.into(attrs, default_attrs)

    {:ok, treaty} =
      %Treaty{}
      |> Treaty.changeset(attrs)
      |> App.Repo.insert()

    treaty
  end
end
