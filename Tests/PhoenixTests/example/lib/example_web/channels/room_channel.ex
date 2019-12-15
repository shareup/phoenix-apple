defmodule ExampleWeb.RoomChannel do
  use Phoenix.Channel

  def join("room:lobby", _params, socket) do
    {:ok, socket}
  end

  def join("room:" <> _room_id, _params, socket) do
    case socket.assigns.user_id do
      nil -> {:error, %{reason: "unauthorized"}}
      _ -> {:ok, socket}
    end
  end

  def handle_in("insert_message", %{"text" => text}, socket) do
    broadcast_from!(socket, "message", %{text: text})
    {:noreply, socket}
  end

  def handle_in("echo", %{"echo" => echo_text}, socket) do
    {:reply, {:ok, %{echo: echo_text}}, socket}
  end

  def handle_in("echo_error", %{"error" => echo_text}, socket) do
    {:reply, {:error, %{error: echo_text}}, socket}
  end

  def handle_in("repeat", %{"echo" => echo_text, "amount" => amount}, socket)
      when is_integer(amount) do
    for n <- 1..amount do
      push(socket, "repeated", %{echo: echo_text, n: n})
    end

    {:reply, {:ok, %{amount: amount}}, socket}
  end
end
