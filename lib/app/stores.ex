defmodule App.Stores do
  @moduledoc """
  Contexto para operações relacionadas a lojas (stores).
  """
  import Ecto.Query, warn: false
  alias App.Repo

  defmodule Store do
    @moduledoc """
    Contexto para operações relacionadas a lojas (stores).
    """
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    schema "stores" do
      field :name, :string
      field :location, :string
      timestamps(type: :utc_datetime_usec)
    end
  end

  @doc """
  Busca uma loja pelo nome (case insensitive). Exemplo: get_store_by!("loja padrao")
  """
  def get_store_by!(name) when is_binary(name) do
    Repo.get_by!(Store, name: name)
  rescue
    Ecto.NoResultsError ->
      # Tenta buscar ignorando case
      Store
      |> where([s], ilike(s.name, ^name))
      |> Repo.one!()
  end
end
