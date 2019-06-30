defmodule ExampleWeb.Socket do
  use Phoenix.Socket

  channel "room:*", ExampleWeb.RoomChannel

  def connect(%{"user_id" => user_id}, socket, _connect_info) do
    id =
      case user_id do
        "anonymous" -> nil
        id -> id
      end

    socket = assign(socket, :user_id, id)
    {:ok, socket}
  end

  def id(socket), do: socket.assigns.user_id
end
