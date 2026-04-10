defmodule IRCane.Channel do
  @moduledoc false
  alias IRCane.Channel.Membership
  alias IRCane.Channel.Modes
  alias IRCane.Channel.State, as: ChannelState
  alias IRCane.Channel.Topic
  alias IRCane.ChannelRegistry
  alias IRCane.Client
  alias IRCane.Protocol.Mode
  alias IRCane.Stats
  alias IRCane.User.State, as: UserState

  require Logger

  use GenServer, restart: :temporary

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts) do
    channel_name = Keyword.fetch!(opts, :name)
    Logger.info("Creating channel: #{channel_name}")
    GenServer.start_link(__MODULE__, opts, name: via_tuple(channel_name))
  end

  @spec broadcast_nick(GenServer.server(), reference(), UserState.t(), String.t()) :: :ok
  def broadcast_nick(pid, ref, from, new_nickname) do
    GenServer.cast(pid, {:broadcast_nick, ref, from, new_nickname})
  end

  @spec broadcast_quit(GenServer.server(), UserState.t(), String.t()) :: :ok
  def broadcast_quit(pid, from, quit_message) do
    GenServer.cast(pid, {:broadcast_quit, from, quit_message})
  end

  @spec join(String.t() | GenServer.server(), UserState.t(), String.t() | nil) ::
          {:ok, pid()} | :noop | {:error, term()}
  def join(channel_name, client, key) when is_binary(channel_name) do
    join(via_tuple(channel_name), client, key)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def join(pid, client, key) do
    GenServer.call(pid, {:join, client, key})
  end

  @spec part(String.t() | GenServer.server(), UserState.t(), String.t()) ::
          {:ok, pid()} | {:error, term()}
  def part(channel_name, client, reason) when is_binary(channel_name) do
    part(via_tuple(channel_name), client, reason)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def part(pid, client, reason) do
    GenServer.call(pid, {:part, client, reason})
  end

  @spec names(String.t() | GenServer.server()) ::
          {String.t(), :public | :secret | :none, [Membership.t()]}
  def names(channel_name) when is_binary(channel_name) do
    names(via_tuple(channel_name))
  catch
    :exit, {:noproc, _} ->
      {channel_name, :none, []}
  end

  def names(pid) do
    GenServer.call(pid, :names)
  end

  @spec privmsg(String.t() | GenServer.server(), UserState.t(), String.t()) ::
          :ok | {:error, term()}
  def privmsg(channel_name, client, message) when is_binary(channel_name) do
    privmsg(via_tuple(channel_name), client, message)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def privmsg(pid, client, message) do
    GenServer.call(pid, {:privmsg, client, message})
  end

  @spec notice(String.t() | GenServer.server(), UserState.t(), String.t()) ::
          :ok | {:error, term()}
  def notice(channel_name, client, message) when is_binary(channel_name) do
    notice(via_tuple(channel_name), client, message)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def notice(pid, client, message) do
    GenServer.cast(pid, {:notice, client, message})
  end

  @spec topic(String.t() | GenServer.server()) ::
          {:ok, {String.t(), Topic.t() | nil}} | {:error, term()}
  def topic(channel_name) when is_binary(channel_name) do
    topic(via_tuple(channel_name))
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def topic(pid) do
    GenServer.call(pid, :topic)
  end

  @spec update_topic(String.t() | GenServer.server(), UserState.t(), String.t()) ::
          :ok | {:error, term()}
  def update_topic(channel_name, client, new_topic) when is_binary(channel_name) do
    update_topic(via_tuple(channel_name), client, new_topic)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def update_topic(pid, client, new_topic) do
    GenServer.call(pid, {:update_topic, client, new_topic})
  end

  @spec mode(String.t() | GenServer.server()) ::
          {:ok, {String.t(), [Mode.t()]}} | {:error, term()}
  def mode(channel_name) when is_binary(channel_name) do
    mode(via_tuple(channel_name))
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def mode(pid) do
    GenServer.call(pid, :mode)
  end

  @spec update_mode(String.t() | GenServer.server(), UserState.t(), [Mode.mode_change()]) ::
          {:ok, {String.t(), [Mode.mode_change()], [atom()]}} | {:error, term()}
  def update_mode(channel_name, client, updates) when is_binary(channel_name) do
    update_mode(via_tuple(channel_name), client, updates)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def update_mode(pid, client, updates) do
    GenServer.call(pid, {:update_mode, client, updates})
  end

  defp via_tuple(channel_name) do
    {:via, Registry, {ChannelRegistry, String.downcase(channel_name)}}
  end

  @impl true
  def init(opts) do
    channel_name = Keyword.fetch!(opts, :name)

    with {:ok, state} <- ChannelState.new(channel_name) do
      Stats.channel_created()
      Logger.info("Channel #{channel_name} process started")

      update_registry_metadata(state)

      {:ok, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Stats.channel_destroyed()
    Logger.notice("Channel #{state.name} process terminated")
  end

  @impl true
  def handle_call({:join, client, key}, _from, state) do
    monitor_ref = Process.monitor(client.pid)

    case ChannelState.join(state, client, monitor_ref, key) do
      {:ok, new_state} ->
        if state.new do
          Logger.notice("User #{client.nickname} created channel #{state.name}")
        else
          Logger.notice("User #{client.nickname} joined channel #{state.name}")
        end

        update_registry_metadata(new_state)

        {:reply, {:ok, self()}, new_state, {:continue, {:notify_join, client}}}

      other ->
        Process.demonitor(monitor_ref)
        {:reply, other, state}
    end
  end

  def handle_call(:names, {pid, _tag}, state) do
    {status, names} = ChannelState.names(state, pid)
    {:reply, {state.name, status, names}, state}
  end

  def handle_call({:privmsg, client, message}, _from, state) do
    case Modes.authorize(state, :speak, client) do
      :ok ->
        {:reply, :ok, state, {:continue, {:notify_privmsg, client, message}}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:part, client, reason}, _from, state) do
    case ChannelState.part(state, client) do
      {:ok, {new_state, membership}} ->
        Logger.info(
          "User #{client.nickname} parted channel #{state.name}#{if reason != "", do: " (#{reason})", else: ""}"
        )

        Process.demonitor(membership.monitor_ref)

        update_registry_metadata(new_state)

        {:reply, {:ok, self()}, new_state, {:continue, {:notify_part, client, reason}}}

      other ->
        {:reply, other, state}
    end
  end

  def handle_call(:topic, {pid, _tag}, state) do
    case ChannelState.topic(state, pid) do
      {:ok, topic} ->
        {:reply, {:ok, {state.name, topic}}, state}

      other ->
        {:reply, other, state}
    end
  end

  def handle_call(:mode, {pid, _tag}, state) do
    case ChannelState.mode(state, pid) do
      {:ok, modes} ->
        {:reply, {:ok, {state.name, modes}}, state}

      other ->
        {:reply, other, state}
    end
  end

  def handle_call({:update_mode, client, updates}, _from, state) do
    case ChannelState.update_mode(state, client, updates) do
      {:ok, {new_state, applied_updates, errors}} ->
        update_registry_metadata(new_state)

        role_changes = ChannelState.role_changes(new_state, state)

        {:reply, {:ok, {state.name, applied_updates, errors}}, new_state,
         {:continue, {:notify_mode, client, applied_updates, role_changes}}}

      other ->
        {:reply, other, state}
    end
  end

  def handle_call({:update_topic, client, new_topic}, _from, state) do
    case ChannelState.update_topic(state, client, new_topic) do
      {:ok, new_state} ->
        Logger.info("User #{client.nickname} set topic in #{state.name}: #{inspect(new_topic)}")
        update_registry_metadata(new_state)
        {:reply, :ok, new_state, {:continue, {:notify_topic, client, new_topic}}}

      other ->
        {:reply, other, state}
    end
  end

  @impl true
  def handle_cast({:broadcast_nick, ref, client, new_nickname}, state) do
    Logger.debug(
      "Broadcasting nick change in #{state.name}: #{client.nickname} -> #{new_nickname}"
    )

    do_broadcast(ref, client, {:nick, client, new_nickname}, state)

    {:noreply, ChannelState.update_member_nickname(state, client)}
  end

  def handle_cast({:broadcast_quit, client, quit_message}, state) do
    Logger.debug("Broadcasting quit in #{state.name}: #{client.nickname} (#{quit_message})")
    do_broadcast({:quit, client.pid}, client, {:quit, client, quit_message}, state)

    {new_state, member} = ChannelState.quit(state, client.pid)
    Process.demonitor(member.monitor_ref)

    update_registry_metadata(new_state)

    terminate_if_empty(new_state)
  end

  def handle_cast({:notice, client, message}, state) do
    with :ok <- Modes.authorize(state, :speak, client) do
      do_broadcast(make_ref(), client, {:notice, client, state.name, message}, state)
    end

    {:noreply, state}
  end

  @impl true
  def handle_continue({:notify_join, client}, state) do
    do_broadcast(make_ref(), client, {:join, client, state.name}, state)
    {:noreply, state}
  end

  def handle_continue({:notify_part, client, reason}, state) do
    do_broadcast(make_ref(), client, {:part, client, state.name, reason}, state)
    terminate_if_empty(state)
  end

  def handle_continue({:notify_topic, client, new_topic}, state) do
    do_broadcast(make_ref(), client, {:topic, client, state.name, new_topic}, state)
    {:noreply, state}
  end

  def handle_continue({:notify_mode, client, applied_changes, role_changes}, state) do
    do_broadcast(make_ref(), client, {:channel_mode, client, state.name, applied_changes}, state)
    Enum.each(role_changes, fn {pid, new_roles} -> Client.update_channel_roles(pid, self(), new_roles) end)
    {:noreply, state}
  end

  def handle_continue({:notify_privmsg, client, message}, state) do
    do_broadcast(make_ref(), client, {:privmsg, client, state.name, message}, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, client_pid, _reason}, state) do
    {new_state, member} = ChannelState.quit(state, client_pid)

    if member do
      quit_message = "User process terminated unexpectedly"

      Logger.debug("Broadcasting quit in #{state.name}: #{member.nickname} (#{quit_message})")

      client = %{
        pid: client_pid,
        nickname: member.nickname,
        username: member.username,
        hostname: member.hostname
      }

      do_broadcast({:quit, client_pid}, client, {:quit, client, quit_message}, state)
      terminate_if_empty(new_state)
    else
      {:noreply, state}
    end
  end

  defp do_broadcast(ref, from, message, state) do
    state.members
    |> Map.keys()
    |> Enum.reject(&(&1 == from.pid))
    |> Enum.each(&Client.deliver(&1, ref, from, message))
  end

  defp terminate_if_empty(state) do
    if ChannelState.empty?(state) do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  defp update_registry_metadata(state) do
    Registry.update_value(ChannelRegistry, String.downcase(state.name), fn _ ->
      ChannelState.metadata(state)
    end)
  end
end
