defmodule ExampleWeb.RoomChannel do
  use Phoenix.Channel

  def join("room:lobby", params, socket) do
    do_join(params, socket)
  end

  def join("room:timeout", %{"timeout" => amount} = params, socket) do
    Process.sleep(amount)

    if %{join: true} = params do
      do_join(params, socket)
    else
      {:error, %{reason: "hard coded timeout"}}
    end
  end

  def join("room:" <> _room_id, params, socket) do
    case socket.assigns.user_id do
      nil -> {:error, %{reason: "unauthorized"}}
      _ -> do_join(params, socket)
    end
  end

  defp do_join(params, socket) do
    socket =
      socket
      |> assign(:join_params, params)

    {:ok, socket}
  end

  def handle_in("insert_message", %{"text" => text}, socket) do
    broadcast_from!(socket, "message", %{text: text})
    {:noreply, socket}
  end

  def handle_in("echo_join_params", _params, socket) do
    body = socket.assigns.join_params
    {:reply, {:ok, body}, socket}
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
