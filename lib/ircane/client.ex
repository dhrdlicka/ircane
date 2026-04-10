defmodule IRCane.Client do
  @moduledoc false
  alias IRCane.Channel
  alias IRCane.Protocol.Message
  alias IRCane.Replies
  alias IRCane.Stats
  alias IRCane.User.State, as: UserState
  alias IRCane.UserRegistry
  alias IRCane.Utils.ReverseDNSResolver

  require Logger

  use GenServer, restart: :temporary

  defstruct transport: nil,
            buffer: "",
            rdns_ref: nil,
            seen_events: :queue.new(),
            user: nil,
            connected_at_mono: nil,
            last_rx_mono: nil,
            ping_sent_at_mono: nil

  @type t :: any()

  @event_dedup_size 1_000
  @max_line 510
  @command_handlers %{
    "NICK" => IRCane.Commands.Nick,
    "PING" => IRCane.Commands.Ping,
    "PONG" => IRCane.Commands.Pong,
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

  @registration_timeout_msec Application.compile_env!(:ircane, :registration_timeout_msec)
  @ping_timeout_msec Application.compile_env!(:ircane, :ping_timeout_msec)
  @heartbeat_interval_msec Application.compile_env!(:ircane, :heartbeat_interval_msec)

  @spec start_link(transport :: {module(), any()}) :: GenServer.on_start()
  def start_link(transport) do
    GenServer.start_link(__MODULE__, transport)
  end

  @spec state(String.t() | GenServer.server()) :: {:ok, t()} | {:error, term()}
  def state(nickname) when is_binary(nickname) do
    state(via_tuple(nickname))
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_nick, nickname}}
  end

  def state(pid) do
    GenServer.call(pid, :state)
  end

  @spec privmsg(String.t() | GenServer.server(), t(), String.t()) :: :ok | {:error, term()}
  def privmsg(nickname, client, message) when is_binary(nickname) do
    privmsg(via_tuple(nickname), client, message)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_nick, nickname}}
  end

  def privmsg(pid, client, message) do
    GenServer.call(pid, {:privmsg, client, message})
  end

  @spec notice(String.t() | GenServer.server(), t(), String.t()) :: :ok | {:error, term()}
  def notice(nickname, client, message) when is_binary(nickname) do
    notice(via_tuple(nickname), client, message)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_nick, nickname}}
  end

  def notice(pid, client, message) do
    GenServer.cast(pid, {:notice, client, message})
  end

  @spec deliver(GenServer.server(), reference(), t(), term()) :: :ok
  def deliver(pid, ref, from, message) do
    GenServer.cast(pid, {:deliver, ref, from, message})
  end

  @spec process_messages(GenServer.server(), [String.t()]) :: :ok
  def process_messages(pid, messages) do
    GenServer.cast(pid, {:process_messages, messages})
  end

  @spec transport_error(GenServer.server(), term()) :: :ok
  def transport_error(pid, reason) do
    GenServer.cast(pid, {:transport_error, reason})
  end

  @impl GenServer
  def init(transport) do
    {:ok,
     %__MODULE__{
       transport: transport,
       user: UserState.new(self()),
       connected_at_mono: System.monotonic_time(:millisecond)
     }, {:continue, :init}}
  end

  @impl GenServer
  def terminate(reason, state) do
    message = state.user.quit_message || "User process terminated unexpectedly"

    state.user.channels
    |> Map.keys()
    |> Enum.each(&Channel.broadcast_quit(&1, state.user, message))

    send_message(state, {:error, "Closing link: (#{host_mask(state)}) [#{message}]"})

    case reason do
      :normal ->
        Logger.debug("Client #{client_id(state)} disconnected normally")

      _ ->
        Logger.error("Client #{client_id(state)} terminated abnormally: #{inspect(reason)}")
    end

    if state.user.registered? do
      Stats.user_quit()
    end
  end

  @impl GenServer
  def handle_call(:state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:privmsg, source, message}, _from, state) do
    send_message(state, {:privmsg, source, state.user.nickname, message})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:deliver, ref, _from, message}, state) do
    if received_event?(state, ref) do
      maybe_timeout(state)
    else
      state
      |> send_message(message)
      |> push_event(ref)
      |> maybe_timeout()
    end
  end

  def handle_cast({:notice, source, message}, state) do
    state
    |> send_message({:notice, source, state.user.nickname, message})
    |> maybe_timeout()
  end

  def handle_cast({:process_messages, messages}, state) do
    new_state =
      messages
      |> Enum.reduce(state, &handle_line/2)
      |> update_last_rx()

    if new_state.user.quit_message do
      {:stop, :normal, new_state}
    else
      {:noreply, new_state, @heartbeat_interval_msec}
    end
  end

  def handle_cast({:transport_error, reason}, state) do
    {:stop, :normal, %{state | user: UserState.quit(state.user, "Transport error: #{reason}")}}
  end

  @impl GenServer
  def handle_continue(:init, %{transport: {mod, ref}} = state) do
    %{hostname: hostname} = mod.finish_handshake(ref)

    send_message(state, :rdns_in_progress)

    %{ref: rdns_ref} =
      Task.Supervisor.async_nolink(IRCane.TaskSupervisor, fn ->
        ReverseDNSResolver.resolve(hostname)
      end)

    new_state =
      %{state | user: UserState.update_hostname(state.user, hostname), rdns_ref: rdns_ref}

    {:noreply, new_state, @heartbeat_interval_msec}
  end

  @impl GenServer
  def handle_info({ref, result}, %{rdns_ref: ref} = state) do
    Process.demonitor(ref, [:flush])

    state
    |> finish_rdns(result)
    |> maybe_register()
    |> maybe_timeout()
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{rdns_ref: ref} = state) do
    state
    |> finish_rdns({:error, {:crashed, reason}})
    |> maybe_register()
    |> maybe_timeout()
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case UserState.pop_channel(state.user, pid) do
      {nil, _} ->
        Logger.warning("Received DOWN message for unknown channel process #{inspect(pid)}")
        maybe_timeout(state)

      {%{name: channel_name}, updated_user} ->
        %{state | user: updated_user}
        |> send_message(
          {:kick, :server, channel_name, state.user.nickname, "Channel process terminated"}
        )
        |> maybe_timeout()
    end
  end

  def handle_info(:timeout, state) do
    maybe_timeout(state)
  end

  defp via_tuple(nickname) do
    {:via, Registry, {UserRegistry, String.downcase(nickname)}}
  end

  defp handle_line(_line, %{user: %{quit_message: message}} = state)
       when not is_nil(message), do: state

  defp handle_line(line, state) when byte_size(line) > @max_line do
    Logger.warning("Line too long from #{client_id(state)}: #{byte_size(line)} bytes")
    send_message(state, :input_too_long)
  end

  defp handle_line(line, state) do
    Logger.debug("[#{client_id(state)}] << #{String.trim(line)}")

    case Message.parse(line) do
      {:ok, %{command: command, params: params}} ->
        command
        |> handle_command(params, state)
        |> maybe_register()

      {:error, reason} ->
        Logger.debug("Failed to parse message from #{client_id(state)}: #{inspect(reason)}")
        state
    end
  end

  defp handle_command(command, params, state) do
    case command |> String.upcase() |> run_command(params, state.user) do
      {:ok, new_state} ->
        %{state | user: new_state}

      {:ok, result, new_state} ->
        send_message(%{state | user: new_state}, result)

      {:error, error} ->
        send_message(state, error)
    end
  end

  defp run_command(command, _params, %{registered?: false} = _user_state)
       when command not in @unregistered_commands do
    {:error, :not_registered}
  end

  defp run_command(command, params, user_state) do
    case Map.get(@command_handlers, command) do
      nil ->
        Logger.debug("Unknown command from #{client_id(user_state)}: #{command}")
        {:error, {:unknown_command, command}}

      handler ->
        handler.handle(params, user_state)
    end
  end

  defp cmd(state, command, params), do: handle_command(command, params, state)

  defp maybe_register(%{transport: {mod, ref}, rdns_ref: nil, user: user} = state) do
    case UserState.try_register(user) do
      {:ok, new_state} ->
        Logger.notice(
          "User registered: #{new_state.nickname}!#{new_state.username}@#{new_state.hostname}"
        )

        Stats.user_registered()

        mod.update_user_info(ref, username: new_state.username)

        %{state | user: new_state}
        |> send_message([:welcome, :your_host, :created, :my_info, :i_support])
        |> cmd("LUSERS", [])
        |> cmd("MOTD", [])

      :noop ->
        state
    end
  end

  defp maybe_register(state) do
    state
  end

  defp maybe_timeout(%{user: %{registered?: false}} = state) do
    now = System.monotonic_time(:millisecond)
    diff = now - state.connected_at_mono

    if diff > @registration_timeout_msec do
      Logger.info(
        "Client #{client_id(state)} did not register within timeout period, disconnecting"
      )

      updated_user = UserState.quit(state.user, "Registration timeout")
      {:stop, :normal, %{state | user: updated_user}}
    else
      {:noreply, state, @heartbeat_interval_msec}
    end
  end

  defp maybe_timeout(%{ping_sent_at_mono: nil} = state) do
    now = System.monotonic_time(:millisecond)
    diff = now - state.last_rx_mono

    if diff > @ping_timeout_msec do
      Logger.info(
        "Client #{client_id(state)} did not send any messages within timeout period, sending PING"
      )

      send_message(state, {:ping, "heartbeat"})
      {:noreply, %{state | ping_sent_at_mono: now}, @heartbeat_interval_msec}
    else
      {:noreply, state, @heartbeat_interval_msec}
    end
  end

  defp maybe_timeout(state) do
    now = System.monotonic_time(:millisecond)
    diff = now - state.ping_sent_at_mono

    if diff > @ping_timeout_msec do
      Logger.info(
        "Client #{client_id(state)} did not respond to PING within timeout period, disconnecting"
      )

      updated_user = UserState.quit(state.user, "Ping timeout (#{diff / 1000} seconds)")
      {:stop, :normal, %{state | user: updated_user}}
    else
      {:noreply, state, @heartbeat_interval_msec}
    end
  end

  defp update_last_rx(state) do
    %{state | last_rx_mono: System.monotonic_time(:millisecond), ping_sent_at_mono: nil}
  end

  defp send_message(state, message) do
    message
    |> List.wrap()
    |> Enum.map(&Replies.format(&1, state.user))
    |> List.flatten()
    |> Enum.each(&do_send_message(&1, state))

    state
  end

  defp do_send_message(%Message{} = message, %{transport: {mod, ref}} = state) do
    raw_message = Message.format(message) <> "\r\n"
    mod.send_message(ref, raw_message)

    Logger.debug("[#{client_id(state)}] >> #{String.trim(raw_message)}")

    :ok
  end

  defp finish_rdns(state, result) do
    case result do
      {:ok, resolved_hostname} ->
        Logger.debug(
          "Reverse DNS lookup successful for #{client_id(state)}: #{resolved_hostname}"
        )

        updated_user = UserState.update_hostname(state.user, resolved_hostname)

        send_message(
          %{state | rdns_ref: nil, user: updated_user},
          {:rdns_successful, resolved_hostname}
        )

      {:error, reason} ->
        Logger.warning("Reverse DNS lookup failed for #{client_id(state)}: #{inspect(reason)}")
        send_message(%{state | rdns_ref: nil}, {:rdns_failed, state.user.hostname})
    end
  end

  defp received_event?(state, event_id) do
    :queue.member(event_id, state.seen_events)
  end

  defp push_event(%{seen_events: events} = state, event_id) do
    queue = :queue.in(event_id, events)

    if :queue.len(queue) > @event_dedup_size do
      {_, new_queue} = :queue.out(queue)
      %{state | seen_events: new_queue}
    else
      %{state | seen_events: queue}
    end
  end

  defp client_id(%{user: user}), do: client_id(user)

  defp client_id(user) do
    user.nickname || host_mask(user)
  end

  defp host_mask(%{user: user}), do: host_mask(user)

  defp host_mask(user) do
    "#{user.username || "unknown"}@#{user.hostname || "unknown"}"
  end
end
