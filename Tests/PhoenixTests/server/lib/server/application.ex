defmodule Server.Application do
  use Application

  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Server.Supervisor]
    Supervisor.start_link([ServerWeb.Endpoint], opts)
  end

  def config_change(changed, _new, removed) do
    ServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
