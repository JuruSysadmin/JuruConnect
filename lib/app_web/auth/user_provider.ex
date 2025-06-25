defmodule App.Auth.UserProvider do
  @callback get_user_by_username(String.t()) :: App.Accounts.User.t() | nil
end
