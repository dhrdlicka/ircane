defmodule IRCane.Channel do
  alias IRCane.Channel.Modes
  alias IRCane.Channel.Membership
  alias IRCane.Channel.State, as: ChannelState
  alias IRCane.Channel.Topic
  alias IRCane.ChannelRegistry
  alias IRCane.Client
  alias IRCane.Protocol.Mode

  require Logger

  use GenServer, restart: :temporary

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts) do
    channel_name = Keyword.fetch!(opts, :name)
    Logger.info("Creating channel: #{channel_name}")
    GenServer.start_link(__MODULE__, opts, name: via_tuple(channel_name))
  end

  def state(channel_name) when is_binary(channel_name) do
    state(via_tuple(channel_name))
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def state(pid) do
    GenServer.call(pid, :state)
  end

  @spec broadcast_nick(GenServer.server(), reference(), Client.t(), String.t()) :: :ok
  def broadcast_nick(pid, ref, from, new_nickname) do
    GenServer.cast(pid, {:broadcast_nick, ref, from, new_nickname})
  end

  @spec broadcast_quit(GenServer.server(), reference(), Client.t(), String.t()) :: :ok
  def broadcast_quit(pid, ref, from, quit_message) do
    GenServer.cast(pid, {:broadcast_quit, ref, from, quit_message})
  end

  @spec join(String.t() | GenServer.server(), Client.t(), String.t() | nil) ::
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

  @spec part(String.t() | GenServer.server(), Client.t(), String.t()) ::
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
          {:ok, {String.t(), [Membership.t()]}} | {:error, term()}
  def names(channel_name) when is_binary(channel_name) do
    names(via_tuple(channel_name))
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def names(pid) do
    GenServer.call(pid, :names)
  end

  @spec privmsg(String.t() | GenServer.server(), Client.t(), String.t()) :: :ok | {:error, term()}
  def privmsg(channel_name, client, message) when is_binary(channel_name) do
    privmsg(via_tuple(channel_name), client, message)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def privmsg(pid, client, message) do
    GenServer.call(pid, {:privmsg, client, message})
  end

  @spec notice(String.t() | GenServer.server(), Client.t(), String.t()) :: :ok | {:error, term()}
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

  @spec update_topic(String.t() | GenServer.server(), Client.t(), String.t()) ::
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

  @spec update_mode(String.t() | GenServer.server(), Client.t(), [Mode.mode_change()]) ::
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

    Registry.update_value(ChannelRegistry, String.downcase(channel_name), fn _ -> channel_name end)

    ChannelState.create(channel_name)
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call({:join, client, key}, _from, state) do
    case ChannelState.join(state, client, key) do
      {:ok, new_state} ->
        if state.new do
          Logger.notice("User #{client.nickname} created channel #{state.name}")
        else
          Logger.notice("User #{client.nickname} joined channel #{state.name}")
        end

        {:reply, {:ok, self()}, new_state, {:continue, {:notify_join, client}}}

      other ->
        {:reply, other, state}
    end
  end

  @impl true
  def handle_call(:names, _from, state) do
    case ChannelState.names(state, nil) do
      {:ok, names} ->
        {:reply, {:ok, {state.name, names}}, state}

      other ->
        {:reply, other, state}
    end
  end

  @impl true
  def handle_call({:privmsg, client, message}, _from, state) do
    with :ok <- Modes.authorize(state, :speak, client) do
      {:reply, :ok, state, {:continue, {:notify_privmsg, client, message}}}
    else
      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:part, client, reason}, _from, state) do
    case ChannelState.part(state, client) do
      {:ok, new_state} ->
        Logger.info(
          "User #{client.nickname} parted channel #{state.name}#{if reason != "", do: " (#{reason})", else: ""}"
        )

        {:reply, {:ok, self()}, new_state, {:continue, {:notify_part, client, reason}}}

      other ->
        {:reply, other, state}
    end
  end

  @impl true
  def handle_call(:topic, _from, state) do
    case ChannelState.topic(state, nil) do
      {:ok, topic} ->
        {:reply, {:ok, {state.name, topic}}, state}

      other ->
        {:reply, other, state}
    end
  end

  @impl true
  def handle_call(:mode, _from, state) do
    case ChannelState.mode(state, nil) do
      {:ok, modes} ->
        {:reply, {:ok, {state.name, modes}}, state}

      other ->
        {:reply, other, state}
    end
  end

  @impl true
  def handle_call({:update_mode, client, updates}, _from, state) do
    case ChannelState.update_mode(state, client, updates) do
      {:ok, {new_state, applied_updates, errors}} ->
        {:reply, {:ok, {state.name, applied_updates, errors}}, new_state,
         {:continue, {:notify_mode, client, applied_updates}}}

      other ->
        {:reply, other, state}
    end
  end

  @impl true
  def handle_call({:update_topic, client, new_topic}, _from, state) do
    case ChannelState.update_topic(state, client, new_topic) do
      {:ok, new_state} ->
        Logger.info("User #{client.nickname} set topic in #{state.name}: #{inspect(new_topic)}")
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

  def handle_cast({:broadcast_quit, ref, client, quit_message}, state) do
    Logger.debug("Broadcasting quit in #{state.name}: #{client.nickname} (#{quit_message})")
    do_broadcast(ref, client, {:quit, client, quit_message}, state)

    state
    |> ChannelState.quit(client)
    |> terminate_if_empty()
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

  @impl true
  def handle_continue({:notify_part, client, reason}, state) do
    do_broadcast(make_ref(), client, {:part, client, state.name, reason}, state)
    terminate_if_empty(state)
  end

  @impl true
  def handle_continue({:notify_topic, client, new_topic}, state) do
    do_broadcast(make_ref(), client, {:topic, client, state.name, new_topic}, state)
    {:noreply, state}
  end

  @impl true
  def handle_continue({:notify_mode, client, applied_changes}, state) do
    do_broadcast(make_ref(), client, {:channel_mode, client, state.name, applied_changes}, state)
    {:noreply, state}
  end

  @impl true
  def handle_continue({:notify_privmsg, client, message}, state) do
    do_broadcast(make_ref(), client, {:privmsg, client, state.name, message}, state)
    {:noreply, state}
  end

  defp do_broadcast(ref, from, message, state) do
    state.members
    |> Map.keys()
    |> Enum.reject(&(&1 == from.pid))
    |> Enum.each(&Client.deliver(&1, ref, from, message))
  end

  defp terminate_if_empty(state) do
    if ChannelState.empty?(state) do
      Logger.notice("Channel #{state.name} shut down after last user left")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end
end
