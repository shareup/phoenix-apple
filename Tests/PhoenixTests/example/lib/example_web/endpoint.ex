defmodule ExampleWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :example

  socket "/socket", ExampleWeb.Socket, websocket: true, longpoll: false

  plug Plug.Static, at: "/", from: :example
end
