defmodule Example.Application do
  use Application

  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Example.Supervisor]
    Supervisor.start_link([ExampleWeb.Endpoint], opts)
  end

  def config_change(changed, _new, removed) do
    ExampleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
