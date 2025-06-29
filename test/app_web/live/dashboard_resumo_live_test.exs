defmodule AppWeb.DashboardResumoLiveTest do
  use AppWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
    :ok
  end

  test "LiveView atualiza ao receber evento PubSub", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")

    # Simula publicação de novos dados
    novos_dados = %{
      sale: 9_999.99,
      cost: 1234.56,
      devolution: 100.0,
      objetivo: 5000.0,
      profit: 20.0,
      percentual: 50.0,
      nfs: 42
    }

    Phoenix.PubSub.broadcast(App.PubSub, "dashboard:updated", {:dashboard_updated, novos_dados})

    assert render(view) =~ "R$ 9.999,99"
    assert render(view) =~ "R$ 1.234,56"
    assert render(view) =~ "R$ 100,00"
    assert render(view) =~ "R$ 5.000,00"
    assert render(view) =~ "20,00%"
    assert render(view) =~ "50,00%"
    assert render(view) =~ "42"
  end
end
