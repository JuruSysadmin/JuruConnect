defmodule App.Auth.UserProvider do
  @moduledoc """
  Provides user-related data for authentication.
  """
  @callback get_user_by_username(String.t()) :: App.Accounts.User.t() | nil
end
