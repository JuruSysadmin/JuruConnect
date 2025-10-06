ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(App.Repo, :manual)

# Configure ExMachina
ExMachina.start(App.Repo)
