defmodule ServerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :server

  socket("/socket", ServerWeb.Socket, websocket: true, longpoll: false)

  plug(Plug.Static, at: "/", from: :server)
end
