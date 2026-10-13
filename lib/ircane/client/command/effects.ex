defmodule IRCane.Client.Command.Effects do
  @moduledoc false

  alias IRCane.Channels
  alias IRCane.Client
  alias IRCane.Protocol.Mode
  alias IRCane.Stats
  alias IRCane.User.State, as: UserState

  require Logger

  @type effect ::
          {:register_nickname, String.t() | nil}
          | {:broadcast_nickname_change, UserState.t()}
          | {:join_channel, String.t(), String.t() | nil}
          | {:part_channel, String.t(), String.t()}
          | {:get_channel_mode, String.t()}
          | {:get_channel_mode_list, String.t(), atom()}
          | {:update_channel_mode, String.t(), [Mode.change()]}
          | {:send_user_message, String.t(), String.t()}
          | {:send_channel_message, String.t(), String.t()}
          | {:send_user_notice, String.t(), String.t()}
          | {:send_channel_notice, String.t(), String.t()}
          | {:get_channel_topic, String.t()}
          | {:update_channel_topic, String.t(), String.t()}
          | {:get_channel_names, String.t()}
          | :get_lusers_stats

  @spec execute(UserState.t(), effect()) ::
          {:ok, UserState.t()} | {:ok, UserState.t(), [term()]} | {:error, term()}
  def execute(state, {:register_nickname, old_nickname}) do
    new_key = String.downcase(state.nickname)

    case Registry.register(IRCane.UserRegistry, new_key, UserState.metadata(state)) do
      {:ok, _} ->
        if not is_nil(old_nickname) do
          old_key = String.downcase(old_nickname)
          Registry.unregister(IRCane.UserRegistry, old_key)
        end

        {:ok, state}

      {:error, {:already_registered, pid}} when pid == self() ->
        {:ok, state}

      {:error, {:already_registered, _}} ->
        Logger.debug("Nickname #{state.nickname} already in use")
        {:error, {:nickname_in_use, state.nickname}}
    end
  end

  def execute(state, {:broadcast_nickname_change, old_state}) do
    if state.nickname != old_state.nickname do
      ref = make_ref()

      state.channels
      |> Map.keys()
      |> Enum.each(&Channels.broadcast_nick(&1, ref, old_state, state.nickname))
    end

    {:ok, state}
  end

  def execute(state, {:join_channel, channel_name, key}) do
    with {:ok, channel_pid} <- Channels.join(channel_name, state, key),
         {:ok, {channel_name, topic}} <- Channels.topic(channel_name, state) do
      {_channel_name, _channel_pid, status, names} = Channels.names(channel_name, state)

      new_state =
        UserState.add_channel(state, channel_pid, channel_name, Process.monitor(channel_pid))

      join_reply = {:join, state, channel_name}
      topic_reply = {:topic, channel_name, topic}
      names_reply = {:names, channel_name, status, names}

      replies =
        if topic, do: [join_reply, topic_reply, names_reply], else: [join_reply, names_reply]

      {:ok, new_state, replies}
    else
      :noop ->
        {:ok, state}

      {:error, reason} ->
        {:ok, state, [reason]}
    end
  end

  def execute(state, {:part_channel, channel_name, reason}) do
    with {:ok, channel_pid} <- Channels.part(channel_name, state, reason) do
      {%{monitor_ref: ref}, new_state} = UserState.pop_channel(state, channel_pid)
      Process.demonitor(ref)

      {:ok, new_state, {:part, state, channel_name, reason}}
    end
  end

  def execute(state, {:get_channel_mode, target}) do
    with {:ok, {channel_name, mode}} <- Channels.mode(target, state) do
      {:ok, state, {:channel_mode_is, channel_name, mode}}
    end
  end

  def execute(state, {:get_channel_mode_list, _target, _mode}) do
    {:ok, state}
  end

  def execute(state, {:update_channel_mode, target, changes}) do
    case Channels.update_mode(target, state, changes) do
      {:ok, {_channel_name, [], errors}} ->
        {:ok, state, errors}

      {:ok, {channel_name, applied_changes, errors}} ->
        {:ok, state, [{:channel_mode, state, channel_name, applied_changes} | errors]}

      {:error, reason} ->
        {:ok, state, [reason]}
    end
  end

  def execute(state, {:send_user_message, target, message}) do
    with :ok <- Client.privmsg(target, state, message) do
      {:ok, state}
    end
  end

  def execute(state, {:send_channel_message, target, message}) do
    with :ok <- Channels.privmsg(target, state, message) do
      {:ok, state}
    end
  end

  def execute(state, {:send_user_notice, target, message}) do
    Client.notice(target, state, message)
    {:ok, state}
  end

  def execute(state, {:send_channel_notice, target, message}) do
    Channels.notice(target, state, message)
    {:ok, state}
  end

  def execute(state, {:get_channel_topic, target}) do
    with {:ok, {channel_name, topic}} <- Channels.topic(target, state) do
      if topic do
        {:ok, state, {:topic, channel_name, topic}}
      else
        {:ok, state, {:no_topic, channel_name}}
      end
    end
  end

  def execute(state, {:update_channel_topic, target, topic}) do
    with :ok <- Channels.update_topic(target, state, topic) do
      {:ok, state, {:topic, state, target, topic}}
    end
  end

  def execute(state, {:get_channel_names, target}) do
    {channel_name, channel_pid, status, names} = Channels.names(target, state)

    names =
      if Map.has_key?(state.channels, channel_pid),
        do: names,
        else: Enum.filter(names, &user_visible?/1)

    {:ok, state, {:names, channel_name, status, names}}
  end

  def execute(state, :get_lusers_stats) do
    stats = Stats.snapshot()

    reply = %{
      users: stats.current_users,
      invisible: 0,
      servers: 1,
      operators: 0,
      unknown: stats.current_connections - stats.current_users,
      channels: stats.current_channels,
      max_users: stats.peak_users
    }

    {:ok, state, {:lusers, reply}}
  end

  defp user_visible?(nickname) do
    case Registry.lookup(IRCane.UserRegistry, String.downcase(nickname)) do
      [{_, %{invisible?: invisible?}}] -> not invisible?
      [] -> false
    end
  end
end
