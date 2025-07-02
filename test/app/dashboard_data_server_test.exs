defmodule App.DashboardDataServerTest do
  use ExUnit.Case, async: true

  alias App.DashboardDataServer

  setup do
    Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
    :ok
  end

  test "publica evento no PubSub ao atualizar dados" do
    # Simula atualização de dados
    DashboardDataServer.handle_info(:fetch, %{
      data: %{},
      last_update: nil,
      api_status: :init,
      api_error: nil
    })

    # Aguarda mensagem do PubSub
    assert_receive {:dashboard_updated, _dados}, 1000
  end
end
