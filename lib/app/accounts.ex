defmodule App.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Accounts.{User, UserOrderHistory}

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a single user by username.

  Returns nil if the User does not exist.

  ## Examples

      iex> get_user_by_username("john_doe")
      %User{}

      iex> get_user_by_username("nonexistent")
      nil

  """
  def get_user_by_username(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Creates a user.

  ## Examples

      iex> create_user(%{field: value})
      {:ok, %User{}}

      iex> create_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  @doc """
  Authenticates a user by username and password.
  """
  def authenticate_user(username, password, _opts \\ []) do
    require Logger
    Logger.info("Authenticating user: #{username}")

    user = Repo.get_by(User, username: username)
    case user do
      nil ->
        Logger.warning("User not found: #{username}")
        Pbkdf2.no_user_verify()
        {:error, :invalid_credentials}
      user ->
        Logger.info("User found: #{user.username}, verifying password")
        if Pbkdf2.verify_pass(password, user.password_hash) do
          Logger.info("Password verified successfully for user: #{user.username}")
          {:ok, user}
        else
          Logger.warning("Invalid password for user: #{username}")
          {:error, :invalid_credentials}
        end
    end
  end

  @doc """
  Registra o acesso de um usuário a um pedido.
  """
  def record_order_access(user_id, order_id) do
    now = App.DateTimeHelper.now()

    case Repo.get_by(UserOrderHistory, user_id: user_id, order_id: order_id) do
      nil ->
        # Primeiro acesso
        %UserOrderHistory{}
        |> UserOrderHistory.changeset(%{
          user_id: user_id,
          order_id: order_id,
          last_accessed_at: now,
          access_count: 1
        })
        |> Repo.insert()

      history ->
        # Acesso subsequente - atualizar contador e timestamp
        history
        |> UserOrderHistory.changeset(%{
          last_accessed_at: now,
          access_count: history.access_count + 1
        })
        |> Repo.update()
    end
  end

  @doc """
  Obtém o histórico de pedidos de um usuário, ordenado por último acesso.
  """
  def get_user_order_history(user_id, limit \\ 10) do
    UserOrderHistory
    |> where(user_id: ^user_id)
    |> order_by([h], desc: h.last_accessed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Obtém estatísticas do histórico de pedidos de um usuário.
  """
  def get_user_order_stats(user_id) do
    query = from h in UserOrderHistory,
      where: h.user_id == ^user_id,
      select: %{
        total_orders: count(h.order_id),
        total_accesses: sum(h.access_count)
      }

    case Repo.one(query) do
      %{total_orders: total_orders, total_accesses: total_accesses} ->
        %{
          total_orders: total_orders || 0,
          total_accesses: total_accesses || 0
        }
      _ ->
        %{total_orders: 0, total_accesses: 0}
    end
  end
end
