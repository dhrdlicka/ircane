defmodule IRCane.Transport.TCP do
  use ThousandIsland.Handler

  require Logger

  alias IRCane.Client
  alias IRCane.ClientSupervisor
  alias IRCane.Replies
  alias IRCane.Stats

  @max_buffer_size 8_192

  def finish_handshake(pid) do
    GenServer.call(pid, :finish_handshake)
  end

  def send_message(pid, message) do
    GenServer.cast(pid, {:send_message, message})
  end

  def update_user_info(pid, user_info) do
    GenServer.cast(pid, {:update_user_info, user_info})
  end

  @impl GenServer
  def handle_call(:finish_handshake, _from, {socket, state}) do
    {:reply, %{hostname: state.hostname}, {socket, state}}
  end

  @impl GenServer
  def handle_cast({:send_message, message}, {socket, state}) do
    case ThousandIsland.Socket.send(socket, message) do
      :ok ->
        {:noreply, {socket, state}, socket.read_timeout}

      {:error, reason} ->
        Logger.error("Failed to send message to #{state.hostname}: #{inspect(reason)}")
        Client.transport_error(state.client_pid, reason)

        {:stop, {:shutdown, :local_closed}, {socket, state}}
    end
  end

  def handle_cast({:update_user_info, user_info}, {socket, state}) do
    {:noreply, {socket, %{state | username: user_info[:username]}}}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, {socket, state})
      when pid == state.client_pid do
    Logger.debug(
      "Client process #{inspect(pid)} has terminated, closing socket for #{state.hostname}"
    )

    {:stop, {:shutdown, :local_closed}, {socket, state}}
  end

  @impl ThousandIsland.Handler
  def handle_connection(socket, _state) do
    {:ok, client_pid} =
      DynamicSupervisor.start_child(ClientSupervisor, {Client, {__MODULE__, self()}})

    hostname =
      case ThousandIsland.Socket.peername(socket) do
        {:ok, {ip_address, _port}} ->
          ip_address
          |> :inet_parse.ntoa()
          |> to_string()

        {:error, reason} ->
          Logger.error("Failed to get peername: #{inspect(reason)}")
          "unknown"
      end

    Process.monitor(client_pid)
    Stats.connection_opened()

    {:continue,
     %{
       client_pid: client_pid,
       username: nil,
       hostname: hostname,
       buffer: ""
     }}
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    case state.buffer <> data do
      new_buffer when byte_size(new_buffer) <= @max_buffer_size ->
        {rest, lines} =
          new_buffer
          |> :binary.split("\n", [:global])
          |> List.pop_at(-1)

        lines =
          Enum.map(lines, fn line -> String.trim_trailing(line, "\r") end)

        Client.process_messages(state.client_pid, lines)

        {:continue, %{state | buffer: rest}}

      _ ->
        Client.transport_error(state.client_pid, :buffer_overflow)
        send_error(state, socket, "Input buffer overflow")

        {:close, state}
    end
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, state) do
    Logger.debug("TCP connection closed for #{state.hostname}")
    Stats.connection_closed()
    Client.transport_error(state.client_pid, :connection_closed)
  end

  @impl ThousandIsland.Handler
  def handle_error(reason, _socket, state) do
    Logger.error("TCP error for #{state.hostname}: #{inspect(reason)}")
    Stats.connection_closed()
    Client.transport_error(state.client_pid, reason)
  end

  defp send_error(state, socket, reason) do
    mask = "#{state.username || "unknown"}@#{state.hostname}"

    {:error, "Closing link: (#{mask}) [#{reason}]"}
    |> Replies.format(%{})
    |> List.wrap()
    |> Enum.each(&ThousandIsland.Socket.send(socket, &1))
  end
end
