defmodule IRCane.Channel do
  alias IRCane.ChannelRegistry
  alias IRCane.Client

  require Logger

  use GenServer, restart: :temporary

  defstruct name: nil,
            members: %{},
            topic: nil,
            permanent?: false

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

  def join(channel_name, client) when is_binary(channel_name) do
    join(via_tuple(channel_name), client)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def join(pid, client) do
    GenServer.call(pid, {:join, client})
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

  def topic(channel_name, client, new_topic) when is_binary(channel_name) do
    topic(via_tuple(channel_name), client, new_topic)
  catch
    :exit, {:noproc, _} ->
      {:error, {:no_such_channel, channel_name}}
  end

  def topic(pid, client, new_topic) do
    GenServer.call(pid, {:topic, client, new_topic})
  end

  defp via_tuple(channel_name) do
    {:via, Registry, {ChannelRegistry, String.downcase(channel_name)}}
  end

  @impl true
  def init(opts) do
    channel_name = Keyword.fetch!(opts, :name)
    permanent? = Keyword.get(opts, :permanent, false)

    Registry.update_value(ChannelRegistry, String.downcase(channel_name), fn _ -> channel_name end)

    state = %__MODULE__{name: channel_name, permanent?: permanent?}
    {:ok, state}
  end

  @impl true
  def handle_call({:join, client}, {client_pid, _}, %{permanent?: false} = state) when map_size(state.members) == 0 do
    # First user to join an empty non-permanent channel becomes operator
    Logger.notice("User #{client.nickname} created channel #{state.name}")
    {:reply, {:ok, self()}, %{state | members: %{client_pid => %{nickname: client.nickname, operator?: true}}}}
  end

  @impl true
  def handle_call({:join, client}, {client_pid, _}, state) do
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
  def handle_call({:topic, client, new_topic}, {client_pid, _}, state) do
    case state.members do
      %{^client_pid => _} ->
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

  defp do_broadcast(ref, from, message, state) do
    state.members
    |> Map.keys()
    |> Enum.reject(&(&1 == from.pid))
    |> Enum.each(&Client.deliver(&1, ref, from, message))
  end

  defp terminate_if_empty(state) do
    if map_size(state.members) == 0 and not state.permanent? do
      Logger.notice("Channel #{state.name} shut down after last user left")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end
end
