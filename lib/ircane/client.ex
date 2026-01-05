defmodule IRCane.Client do
  alias IRCane.Channel
  alias IRCane.Message
  alias IRCane.NickRegistry
  alias IRCane.Replies

  require Logger

  use GenServer, restart: :temporary

  defstruct socket: nil,
            buffer: "",
            pid: nil,
            nickname: nil,
            username: nil,
            hostname: nil,
            realname: nil,
            registered?: false,
            disconnecting?: false,
            operator?: true,
            away_message: nil,
            quit_message: nil,
            seen_events: :queue.new(),
            joined_channels: MapSet.new()

  @event_dedup_size 1_000
  @max_buffer 8_192
  @max_line 510
  @command_handlers %{
    "NICK" => IRCane.Commands.Nick,
    "PING" => IRCane.Commands.Ping,
    "USER" => IRCane.Commands.User,
    "MOTD" => IRCane.Commands.Motd,
    "LUSERS" => IRCane.Commands.Lusers,
    "PRIVMSG" => IRCane.Commands.Privmsg,
    "NOTICE" => IRCane.Commands.Notice,
    "JOIN" => IRCane.Commands.Join,
    "PART" => IRCane.Commands.Part,
    "NAMES" => IRCane.Commands.Names,
    "TOPIC" => IRCane.Commands.Topic,
    "QUIT" => IRCane.Commands.Quit
  }
  @unregistered_commands ["NICK", "USER"]

  @spec start_link(socket :: :inet.socket()) :: GenServer.on_start()
  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  @spec socket_ready(pid :: pid()) :: :ok
  def socket_ready(pid) do
    GenServer.cast(pid, :socket_ready)
  end

  def deliver(pid, ref, from, message) do
    GenServer.cast(pid, {:deliver, ref, from, message})
  end

  def privmsg(nickname, client, message) when is_binary(nickname) do
    privmsg(via_tuple(nickname), client, message)
  end

  def privmsg(pid, client, message) do
    GenServer.call(pid, {:privmsg, client, message})
  end

  def notice(nickname, client, message) when is_binary(nickname) do
    notice(via_tuple(nickname), client, message)
  end

  def notice(pid, client, message) do
    GenServer.cast(pid, {:notice, client, message})
  end

  @impl true
  def init(socket) do
    {:ok, %__MODULE__{socket: socket, pid: self()}, {:continue, :init}}
  end

  @impl true
  def handle_call({:privmsg, source, message}, _from, state) do
    {:privmsg, source, state.nickname, message}
    |> Replies.format_message(state.nickname)
    |> Enum.each(&send_message(&1, state))

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:socket_ready, state) do
    :inet.setopts(state.socket, active: :once)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:deliver, ref, _from, message}, state) do
    if not :queue.member(ref, state.seen_events) do
      message
      |> Replies.format_message(state.nickname)
      |> Enum.each(&send_message(&1, state))

      {:noreply, %{state | seen_events: push_event(state.seen_events, ref)}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:notice, source, message}, state) do
    {:notice, source, state.nickname, message}
    |> Replies.format_message(state.nickname)
    |> Enum.each(&send_message(&1, state))

    {:noreply, state}
  end

  @impl true
  def handle_continue(:init, state) do
    with {:ok, {ipv4, _port}} <- :inet.peername(state.socket) do
      hostname =
        ipv4
        |> :inet_parse.ntoa()
        |> to_string()

      Logger.debug("Client connection initialized from #{hostname}")

      {:noreply, %{state | hostname: hostname}}
    end
  end

  @impl true
  def handle_info({:tcp, socket, packet}, state) do
    Logger.debug("[#{state.nickname || state.hostname || "unknown"}] Received: #{String.trim(packet)}")

    state = handle_packet(packet, state)

    :inet.setopts(socket, active: :once)

    if state.disconnecting? do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.debug("Socket closed for #{state.nickname || state.hostname || "unknown"}")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.error("TCP error: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  @impl true
  def terminate(reason, state) do
    identifier = state.nickname || state.hostname || "unknown"
    quit_message = state.quit_message || "Internal Server Error"
    quit_ref = make_ref()

    Enum.each(state.joined_channels, &Channel.broadcast_quit(&1, quit_ref, state, quit_message))

    message =
      %Message{
        command: "ERROR",
        params: [quit_message]
      }

    send_message(message, state)
    :gen_tcp.close(state.socket)

    case reason do
      :normal ->
        Logger.debug("Client #{identifier} disconnected normally")

      _ ->
        Logger.error("Client #{identifier} terminated abnormally: #{inspect(reason)}")
    end
  end

  defp via_tuple(nickname) do
    {:via, Registry, {NickRegistry, String.downcase(nickname)}}
  end

  defp handle_packet(packet, state) do
    buffer = state.buffer <> packet

    if byte_size(buffer) > @max_buffer do
      Logger.warning("Buffer overflow for client #{state.nickname || state.hostname || "unknown"}: #{byte_size(buffer)} bytes")
      %{state | disconnecting?: true, quit_message: "Buffer overflow"}
    else
      {lines, rest} = split_lines(buffer)
      Enum.reduce(lines, %{state | buffer: rest}, &handle_line/2)
    end
  end

  defp split_lines(buffer) do
    {rest, lines} =
      buffer
      |> :binary.split("\n", [:global])
      |> List.pop_at(-1)

    lines =
      Enum.map(lines, fn line -> String.trim_trailing(line, "\r") end)

    {lines, rest}
  end

  defp handle_line(line, state) when byte_size(line) > @max_line do
    Logger.warning("Line too long from #{state.nickname || state.hostname || "unknown"}: #{byte_size(line)} bytes")
    state
  end

  defp handle_line(line, state) do
    with {:ok, %{command: command, params: params}} <- Message.parse(line) do
      command
      |> String.upcase()
      |> handle_command(params, state)
      |> register()
    else
      {:error, reason} ->
        Logger.debug("Failed to parse message from #{state.nickname || state.hostname || "unknown"}: #{inspect(reason)}")
        state
    end
  end

  defp handle_command(command, params, state) do
    case run_command(command, params, state) do
      {:ok, new_state} ->
        new_state

      {:ok, result, new_state} ->
        result
        |> Replies.format_message(new_state.nickname || "*")
        |> Enum.each(&send_message(&1, new_state))

        new_state

      {:error, error} ->
        error
        |> Replies.format_message(state.nickname || "*")
        |> Enum.each(&send_message(&1, state))

        state
    end
  end

  defp run_command(command, _params, %{registered?: false} = _state)
  when command not in @unregistered_commands do
    {:error, :not_registered}
  end

  defp run_command(command, params, state) do
    case Map.get(@command_handlers, command) do
      nil ->
        Logger.debug("Unknown command from #{state.nickname || state.hostname || "unknown"}: #{command}")
        {:error, {:unknown_command, command}}

      handler ->
        handler.handle(params, state)
    end
  end

  defp register(%{registered?: false,nickname: nick, username: user} = state) when not is_nil(nick) and not is_nil(user) do
    Logger.notice("User registered: #{state.nickname}!#{state.username}@#{state.hostname}")

    [:welcome, :your_host, :created, :my_info, :i_support]
    |> Replies.format_message(state.nickname)
    |> Enum.each(&send_message(&1, state))

    state = %{state | registered?: true}

    handle_command("LUSERS", [], state)
    handle_command("MOTD", [], state)

    state
  end

  defp register(state) do
    state
  end

  defp send_message(%Message{} = message, state) do
    raw_message = Message.build(message) <> "\r\n"
    :gen_tcp.send(state.socket, raw_message)
    Logger.debug("[#{state.nickname || state.hostname || "unknown"}] Sent: #{String.trim(raw_message)}")
    :ok
  end

  defp push_event(events, event_id) do
    queue = :queue.in(event_id, events)

    if :queue.len(queue) > @event_dedup_size do
      {_, queue} = :queue.out(queue)
      queue
    else
      queue
    end
  end
end
