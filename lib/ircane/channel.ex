defmodule IRCane.Channel do
  @moduledoc false
  alias IRCane.Channel.Modes
  alias IRCane.Channel.State, as: ChannelState
  alias IRCane.ChannelRegistry
  alias IRCane.Client
  alias IRCane.Stats
  alias IRCane.User.State, as: UserState

  require Logger

  use GenServer, restart: :temporary

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts) do
    channel_name = Keyword.fetch!(opts, :name)
    Logger.info("Creating channel: #{channel_name}")
    GenServer.start_link(__MODULE__, opts, name: via(channel_name))
  end

  @spec request(GenServer.server(), UserState.t(), term()) ::
          :ok | {:ok, term()} | {:error, term()}
  def request(server, client, op) do
    GenServer.call(server, {:request, client, op})
  end

  @spec broadcast_nick(GenServer.server(), reference(), UserState.t(), String.t()) :: :ok
  def broadcast_nick(server, ref, from, new_nickname) do
    GenServer.cast(server, {:broadcast_nick, ref, from, new_nickname})
  end

  @spec via(String.t()) :: GenServer.name()
  def via(channel_name) do
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
  def handle_call({:request, %{pid: pid} = client, op}, {pid, _tag}, state) do
    handle_request(state, client, op)
  end

  @impl true
  def handle_cast({:broadcast_nick, ref, client, new_nickname}, state) do
    Logger.debug(
      "Broadcasting nick change in #{state.name}: #{client.nickname} -> #{new_nickname}"
    )

    do_broadcast(ref, client, {:nick, client, new_nickname}, state)

    {:noreply, ChannelState.update_member_nickname(state, client)}
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
    Client.update_channel_roles(client.pid, self(), state.members[client.pid].roles)
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

    Enum.each(role_changes, fn {pid, new_roles} ->
      Client.update_channel_roles(pid, self(), new_roles)
    end)

    {:noreply, state}
  end

  def handle_continue({:notify_privmsg, client, message}, state) do
    do_broadcast(make_ref(), client, {:privmsg, client, state.name, message}, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, client_pid, reason}, state) do
    {new_state, member} = ChannelState.quit(state, client_pid)

    if member do
      quit_message =
        case reason do
          {:shutdown, {:quit, quit_message}} -> quit_message
          _ -> "User process terminated unexpectedly"
        end

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

  defp handle_request(state, client, {:join, key}) do
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

  defp handle_request(state, client, :names) do
    {status, names} = ChannelState.names(state, client)
    {:reply, {state.name, self(), status, names}, state}
  end

  defp handle_request(state, client, {:privmsg, message}) do
    case Modes.authorize(state, :speak, client) do
      :ok ->
        {:reply, :ok, state, {:continue, {:notify_privmsg, client, message}}}

      error ->
        {:reply, error, state}
    end
  end

  defp handle_request(state, client, {:part, reason}) do
    case ChannelState.part(state, client) do
      {:ok, {new_state, membership}} ->
        Logger.info(
          "User #{client.nickname} parted channel #{state.name}#{if reason != "", do: " (#{reason})", else: ""}"
        )

        Process.demonitor(membership.monitor_ref, [:flush])

        update_registry_metadata(new_state)

        {:reply, {:ok, self()}, new_state, {:continue, {:notify_part, client, reason}}}

      other ->
        {:reply, other, state}
    end
  end

  defp handle_request(state, client, :topic) do
    case ChannelState.topic(state, client) do
      {:ok, topic} ->
        {:reply, {:ok, {state.name, topic}}, state}

      other ->
        {:reply, other, state}
    end
  end

  defp handle_request(state, client, :mode) do
    case ChannelState.mode(state, client) do
      {:ok, modes} ->
        {:reply, {:ok, {state.name, modes}}, state}

      other ->
        {:reply, other, state}
    end
  end

  defp handle_request(state, client, {:update_mode, updates}) do
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

  defp handle_request(state, client, {:update_topic, new_topic}) do
    case ChannelState.update_topic(state, client, new_topic) do
      {:ok, new_state} ->
        Logger.info("User #{client.nickname} set topic in #{state.name}: #{inspect(new_topic)}")
        update_registry_metadata(new_state)
        {:reply, :ok, new_state, {:continue, {:notify_topic, client, new_topic}}}

      other ->
        {:reply, other, state}
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
