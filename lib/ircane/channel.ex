defmodule IRCane.Channel do
  alias IRCane.ChannelRegistry
  alias IRCane.Client

  require Logger

  use GenServer, restart: :temporary

  defstruct name: nil,
            members: %{},
            topic: nil,
            bans: [],
            channel_limit: nil,
            key: nil,
            invite_only?: false,
            moderated?: false,
            secret?: false,
            protected_topic?: true,
            no_external_messages?: true

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts) do
    channel_name = Keyword.fetch!(opts, :name)
    Logger.info("Creating channel: #{channel_name}")
    GenServer.start_link(__MODULE__, opts, name: via_tuple(channel_name))
  end

  def broadcast_nick(pid, ref, from, new_nickname) do
    GenServer.cast(pid, {:broadcast_nick, ref, from, new_nickname})
  end

  def broadcast_quit(pid, ref, from, quit_message) do
    GenServer.cast(pid, {:broadcast_quit, ref, from, quit_message})
  end

  def join(channel_name, client, key) when is_binary(channel_name) do
    join(via_tuple(channel_name), client, key)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def join(pid, client, key) do
    GenServer.call(pid, {:join, client, key})
  end

  def part(channel_name, client, reason) when is_binary(channel_name) do
    part(via_tuple(channel_name), client, reason)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def part(pid, client, reason) do
    GenServer.call(pid, {:part, client, reason})
  end

  def names(channel_name) when is_binary(channel_name) do
    names(via_tuple(channel_name))
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def names(pid) do
    GenServer.call(pid, :names)
  end

  def privmsg(channel_name, client, message) when is_binary(channel_name) do
    privmsg(via_tuple(channel_name), client, message)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def privmsg(pid, client, message) do
    GenServer.call(pid, {:privmsg, client, message})
  end

  def notice(channel_name, client, message) when is_binary(channel_name) do
    notice(via_tuple(channel_name), client, message)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def notice(pid, client, message) do
    GenServer.cast(pid, {:notice, client, message})
  end

  def topic(channel_name) when is_binary(channel_name) do
    topic(via_tuple(channel_name))
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def topic(pid) do
    GenServer.call(pid, :topic)
  end

  def update_topic(channel_name, client, new_topic) when is_binary(channel_name) do
    update_topic(via_tuple(channel_name), client, new_topic)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def update_topic(pid, client, new_topic) do
    GenServer.call(pid, {:update_topic, client, new_topic})
  end

  def mode(channel_name) when is_binary(channel_name) do
    mode(via_tuple(channel_name))
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def mode(pid) do
    GenServer.call(pid, :mode)
  end

  def update_mode(channel_name, operations, client) when is_binary(channel_name) do
    update_mode(via_tuple(channel_name), operations, client)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def update_mode(pid, operations, client) do
    GenServer.call(pid, {:update_mode, operations, client})
  end

  defp via_tuple(channel_name) do
    {:via, Registry, {ChannelRegistry, String.downcase(channel_name)}}
  end

  @impl true
  def init(opts) do
    channel_name = Keyword.fetch!(opts, :name)

    Registry.update_value(ChannelRegistry, String.downcase(channel_name), fn _ -> channel_name end)

    state = %__MODULE__{name: channel_name}
    {:ok, state}
  end

  @impl true
  def handle_call({:join, client, _key}, {client_pid, _}, state) when map_size(state.members) == 0 do
    # First user to join an empty non-permanent channel becomes operator
    Logger.notice("User #{client.nickname} created channel #{state.name}")
    {:reply, {:ok, self()}, %{state | members: %{client_pid => %{nickname: client.nickname, operator?: true}}}}
  end

  @impl true
  def handle_call({:join, client, _key}, {client_pid, _}, state) do
    case state.members do
      %{^client_pid => _} ->
        {:reply, :noop, state}

      _ ->
        Logger.info("User #{client.nickname} joined channel #{state.name}")

        membership = %{nickname: client.nickname}
        members = Map.put(state.members, client_pid, membership)
        {:reply, {:ok, self()}, %{state | members: members}, {:continue, {:notify_join, client}}}
    end
  end

  @impl true
  def handle_call(:names, {_client_pid, _}, state) do
    {:reply, {:ok, {state.name, Map.values(state.members)}}, state}
  end

  @impl true
  def handle_call({:privmsg, from, message}, _from, state) do
    do_broadcast(make_ref(), from, {:privmsg, from, state.name, message}, state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:part, client, reason}, {client_pid, _}, state) do
    case state.members do
      %{^client_pid => _} ->
        Logger.info("User #{client.nickname} parted channel #{state.name}#{if reason != "", do: " (#{reason})", else: ""}")
        new_members = Map.delete(state.members, client_pid)
        {:reply, {:ok, self()}, %{state | members: new_members}, {:continue, {:notify_part, client, reason}}}

      _ ->
        {:reply, {:error, {:not_on_channel, state.name}}, state}
    end
  end

  @impl true
  def handle_call(:topic, _from, state) do
    {:reply, {:ok, {state.name, state.topic}}, state}
  end

  @impl true
  def handle_call(:mode, _from, state) do
    modes = []

    modes = if state.invite_only?, do: [:invite_only | modes], else: modes
    modes = if state.moderated?, do: [:moderated | modes], else: modes
    modes = if state.secret?, do: [:secret | modes], else: modes
    modes = if state.protected_topic?, do: [:protected_topic | modes], else: modes
    modes = if state.no_external_messages?, do: [:no_external_messages | modes], else: modes
    modes = if state.channel_limit, do: [{:channel_limit, state.channel_limit} | modes], else: modes
    modes = if state.key, do: [{:key, state.key} | modes], else: modes

    {:reply, {:ok, {state.name, modes}}, state}
  end

  @impl true
  def handle_call({:update_mode, operations, client}, {client_pid, _}, state) do
    # Check if user is channel operator
    case state.members do
      %{^client_pid => %{operator?: true}} ->
        {new_state, applied_changes, errors} =
          Enum.reduce(operations, {state, [], []}, &apply_mode/2)

        {:reply, {:ok, {state.name, applied_changes, errors}}, new_state, {:continue, {:notify_mode, client, applied_changes}}}

      _ ->
        {:reply, {:error, {:chan_o_privs_needed, state.name}}, state}
    end
  end

  @impl true
  def handle_call({:update_topic, client, new_topic}, {client_pid, _}, state) do
        topic =
          %{
            topic: new_topic,
            nick: client.nickname,
            set_at: DateTime.utc_now()
          }

        Logger.info("User #{client.nickname} set topic in #{state.name}: #{inspect(new_topic)}")
        {:reply, :ok, %{state | topic: topic}, {:continue, {:notify_topic, client, new_topic}}}

      _ ->
        {:reply, {:error, {:not_on_channel, state.name}}, state}
    end
  end

  @impl true
  def handle_cast({:broadcast_nick, ref, client, new_nickname}, state) do
    Logger.debug("Broadcasting nick change in #{state.name}: #{client.nickname} -> #{new_nickname}")
    do_broadcast(ref, client, {:nick, client, new_nickname}, state)

    membership = state.members[client.pid]
    members = %{state.members | client.pid => %{membership | nickname: new_nickname}}
    {:noreply, %{state | members: members}}
  end

  def handle_cast({:broadcast_quit, ref, client, quit_message}, state) do
    Logger.debug("Broadcasting quit in #{state.name}: #{client.nickname} (#{quit_message})")
    do_broadcast(ref, client, {:quit, client, quit_message}, state)

    members = Map.delete(state.members, client.pid)
    {:noreply, %{state | members: members}}
  end

  def handle_cast({:notice, from, message}, state) do
    do_broadcast(make_ref(), from, {:notice, from, state.name, message}, state)
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

  defp do_broadcast(ref, from, message, state) do
    state.members
    |> Map.keys()
    |> Enum.reject(&(&1 == from.pid))
    |> Enum.each(&Client.deliver(&1, ref, from, message))
  end

  defp terminate_if_empty(state) do
    if map_size(state.members) == 0 do
      Logger.notice("Channel #{state.name} shut down after last user left")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  defp apply_mode({_op, :invite_only} = mode, acc), do: apply_boolean_mode(acc, :invite_only?, mode)
  defp apply_mode({_op, :moderated} = mode, acc), do: apply_boolean_mode(acc, :moderated?, mode)
  defp apply_mode({_op, :secret} = mode, acc), do: apply_boolean_mode(acc, :secret?, mode)
  defp apply_mode({_op, :protected_topic} = mode, acc), do: apply_boolean_mode(acc, :protected_topic?, mode)
  defp apply_mode({_op, :no_external_messages} = mode, acc), do: apply_boolean_mode(acc, :no_external_messages?, mode)

  defp apply_mode({:add, {:channel_limit, new_limit}}, {state, changes, errors}) when state.channel_limit != new_limit do
    {%{state | channel_limit: new_limit}, [{:add, {:channel_limit, new_limit}} | changes], errors}
  end

  defp apply_mode({:remove, :channel_limit}, {state, changes, errors}) when not is_nil(state.channel_limit) do
    {%{state | channel_limit: nil}, [{:remove, :channel_limit} | changes], errors}
  end

  defp apply_mode({:add, {:key, new_key}}, {%{key: nil} = state, changes, errors}) do
    {%{state | key: new_key}, [{:add, {:key, new_key}} | changes], errors}
  end

  defp apply_mode({:remove, {:key, key}}, {state, changes, errors}) when state.key == key do
    {%{state | key: nil}, [{:remove, :key} | changes], errors}
  end

  defp apply_mode(_, acc), do: acc

  defp apply_boolean_mode({state, changes, errors}, field_name, {op, _mode_name} = change) do
    case {op, Map.get(state, field_name)} do
      {:add, false} -> {Map.put(state, field_name, true), [change | changes], errors}
      {:remove, true} -> {Map.put(state, field_name, false), [change | changes], errors}
      _ -> {state, changes, errors}
    end
  end
end
