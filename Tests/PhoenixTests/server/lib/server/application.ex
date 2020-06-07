defmodule Server.Application do
  use Application

  def start(_type, _args) do
    children = [
      ServerWeb.Endpoint,
      {Phoenix.PubSub, [name: Server.PubSub, adapter: Phoenix.PubSub.PG2]}
    ]

    opts = [strategy: :one_for_one, name: Server.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    ServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
