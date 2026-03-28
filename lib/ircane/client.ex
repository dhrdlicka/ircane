defmodule IRCane.Client do
  alias IRCane.Channel
  alias IRCane.Protocol.Message
  alias IRCane.UserRegistry
  alias IRCane.Replies
  alias IRCane.Utils.ReverseDNSResolver

  require Logger

  use GenServer, restart: :temporary

  defstruct transport: nil,
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
            joined_channels: %{}

  @type t :: any()

  @event_dedup_size 1_000
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
    "MODE" => IRCane.Commands.Mode,
    "QUIT" => IRCane.Commands.Quit
  }
  @unregistered_commands ["NICK", "USER"]

  @spec start_link(transport :: {module(), any()}) :: GenServer.on_start()
  def start_link(transport) do
    GenServer.start_link(__MODULE__, transport)
  end

  def state(nickname) when is_binary(nickname) do
    state(via_tuple(nickname))
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_nick, nickname}}
  end

  def state(pid) do
    GenServer.call(pid, :state)
  end

  def deliver(pid, ref, from, message) do
    GenServer.cast(pid, {:deliver, ref, from, message})
  end

  def privmsg(nickname, client, message) when is_binary(nickname) do
    privmsg(via_tuple(nickname), client, message)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_nick, nickname}}
  end

  def privmsg(pid, client, message) do
    GenServer.call(pid, {:privmsg, client, message})
  end

  def notice(nickname, client, message) when is_binary(nickname) do
    notice(via_tuple(nickname), client, message)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_nick, nickname}}
  end

  def notice(pid, client, message) do
    GenServer.cast(pid, {:notice, client, message})
  end

  def process_messages(pid, messages) do
    GenServer.cast(pid, {:process_messages, messages})
  end

  def transport_error(pid, reason) do
    GenServer.cast(pid, {:transport_error, reason})
  end

  @impl true
  def init(transport) do
    {:ok, %__MODULE__{transport: transport, pid: self()}, {:continue, :init}}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call({:privmsg, source, message}, _from, state) do
    {:privmsg, source, state.nickname, message}
    |> Replies.format_message(state.nickname)
    |> Enum.each(&send_message(&1, state))

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:deliver, ref, _from, message}, state) do
    if :queue.member(ref, state.seen_events) do
      {:noreply, state}
    else
      message
      |> Replies.format_message(state.nickname)
      |> Enum.each(&send_message(&1, state))

      {:noreply, %{state | seen_events: push_event(state.seen_events, ref)}}
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
  def handle_cast({:process_messages, messages}, state) do
    new_state = Enum.reduce(messages, state, &handle_line/2)

    if state.disconnecting? do
      {:stop, :normal, new_state}
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:transport_error, reason}, state) do
    {:stop, :normal, %{state | disconnecting?: true, quit_message: inspect(reason)}}
  end

  @impl true
  def handle_continue(:init, %{transport: {mod, ref}} = state) do
    %{hostname: hostname} = mod.finish_handshake(ref)

    case ReverseDNSResolver.resolve(hostname) do
      {:ok, resolved_hostname} ->
        Logger.debug("Reverse DNS lookup successful for #{hostname}: #{resolved_hostname}")
        {:noreply, %{state | hostname: resolved_hostname}}

      {:error, reason} ->
        Logger.warning("Reverse DNS lookup failed for #{hostname}: #{inspect(reason)}")
        {:noreply, %{state | hostname: hostname}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {channel_info, joined_channels} = Map.pop(state.joined_channels, pid)

    if channel_info do
      {:kick, :server, channel_info.name, state.nickname,
       "Channel process terminated unexpectedly"}
      |> Replies.format_message(state.nickname)
      |> Enum.each(&send_message(&1, state))

      {:noreply, %{state | joined_channels: joined_channels}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    identifier = state.nickname || state.hostname || "unknown"
    message = state.quit_message || "User process terminated unexpectedly"

    state.joined_channels
    |> Map.keys()
    |> Enum.each(&Channel.broadcast_quit(&1, state, message))

    mask = "#{inspect(state.username)}@#{state.hostname}"

    {:error, "Closing link: (#{mask}) [#{message}]"}
    |> Replies.format_message(state.nickname || "*")
    |> Enum.each(&send_message(&1, state))

    case reason do
      :normal ->
        Logger.debug("Client #{identifier} disconnected normally")

      _ ->
        Logger.error("Client #{identifier} terminated abnormally: #{inspect(reason)}")
    end
  end

  defp via_tuple(nickname) do
    {:via, Registry, {UserRegistry, String.downcase(nickname)}}
  end

  defp handle_line(line, state) when byte_size(line) > @max_line do
    :input_too_long
    |> Replies.format_message(state.nickname || "*")
    |> Enum.each(&send_message(&1, state))

    Logger.warning(
      "Line too long from #{state.nickname || state.hostname || "unknown"}: #{byte_size(line)} bytes"
    )

    state
  end

  defp handle_line(line, state) do
    Logger.debug(
      "[#{state.nickname || state.hostname || "unknown"}] << #{String.trim(line)}"
    )

    case Message.parse(line) do
      {:ok, %{command: command, params: params}} ->
        command
        |> String.upcase()
        |> handle_command(params, state)
        |> register()

      {:error, reason} ->
        Logger.debug(
          "Failed to parse message from #{state.nickname || state.hostname || "unknown"}: #{inspect(reason)}"
        )

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
        Logger.debug(
          "Unknown command from #{state.nickname || state.hostname || "unknown"}: #{command}"
        )

        {:error, {:unknown_command, command}}

      handler ->
        handler.handle(params, state)
    end
  end

  defp register(%{registered?: false, nickname: nick, username: user} = state)
       when not is_nil(nick) and not is_nil(user) do
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

  defp send_message(%Message{} = message, %{transport: {mod, ref}} = state) do
    raw_message = Message.format(message) <> "\r\n"
    mod.send_message(ref, raw_message)

    Logger.debug(
      "[#{state.nickname || state.hostname || "unknown"}] >> #{String.trim(raw_message)}"
    )

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
