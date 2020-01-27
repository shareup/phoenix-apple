defmodule ExampleWeb.Socket do
  require Logger

  # hack to be able to send custom commands to the socket without needing a channel
  # MUST be before use Phoenix.Socket
  def handle_in({"disconnect", opts}, {state, socket}) do
    # only support text commands
    :text = Keyword.fetch!(opts, :opcode)

    ExampleWeb.Endpoint.broadcast(id(socket), "disconnect", %{})

    {:ok, {state, socket}}
  end

  use Phoenix.Socket

  channel "room:*", ExampleWeb.RoomChannel

  def connect(%{"disconnect" => "soon"} = params, socket, connect_info) do
    # or else we will recurse into this connection function
    params = Map.delete(params, "disconnect")

    {:ok, socket} = connect(params, socket, connect_info)

    pid =
      spawn(fn ->
        receive do
          :disconnect ->
            ExampleWeb.Endpoint.broadcast(id(socket), "disconnect", %{})
        end
      end)

    Process.send_after(pid, :disconnect, 400)

    {:ok, socket}
  end

  def connect(%{"user_id" => user_id}, socket, _connect_info) do
    id =
      case user_id do
        "anonymous" -> nil
        id -> id
      end

    socket =
      socket
      |> assign(:user_id, id)
      |> assign(:counter, 1)

    {:ok, socket}
  end

  def id(socket), do: "users_socket:#{socket.assigns.user_id}"
end
