defmodule IRCane.Command.Effects do
  @moduledoc false

  alias IRCane.Channel
  alias IRCane.ChannelSupervisor
  alias IRCane.Client
  alias IRCane.User.State, as: UserState

  require Logger

  @type effect ::
          {:register_nickname, String.t() | nil}
          | {:broadcast_nickname_change, UserState.t()}
          | {:join_channel, String.t(), String.t() | nil}
          | {:part_channel, String.t(), String.t()}

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
      |> Enum.each(&Channel.broadcast_nick(&1, ref, old_state, state.nickname))
    end

    {:ok, state}
  end

  def execute(state, {:join_channel, channel_name, key}) do
    with {:ok, channel_pid} <- do_join(channel_name, key, state),
         {:ok, {channel_name, topic}} <- Channel.topic(channel_pid) do
      {_channel_name, _channel_pid, status, names} = Channel.names(channel_pid)

      new_state =
        UserState.add_channel(state, channel_pid, channel_name, Process.monitor(channel_pid))

      replies =
        if topic do
          [
            {:join, state, channel_name},
            {:topic, channel_name, topic},
            {:names, channel_name, status, names}
          ]
        else
          [
            {:join, state, channel_name},
            {:names, channel_name, status, names}
          ]
        end

      {:ok, new_state, replies}
    else
      :noop ->
        {:ok, state}

      error ->
        {:ok, state, [error]}
    end
  end

  def execute(state, {:part_channel, channel_name, reason}) do
    with {:ok, channel_pid} <- Channel.part(channel_name, state, reason) do
      {%{monitor_ref: ref}, new_state} = UserState.pop_channel(state, channel_pid)
      Process.demonitor(ref)

      {:ok, new_state, {:part, state, channel_name, reason}}
    end
  end

  def execute(state, {:get_channel_mode, target}) do
    with {:ok, {channel_name, mode}} <- Channel.mode(target) do
      {:ok, state, {:channel_mode_is, channel_name, mode}}
    end
  end

  def execute(state, {:get_channel_mode_list, _target, _mode}) do
    {:ok, state}
  end

  def execute(state, {:update_channel_mode, target, changes}) do
    case Channel.update_mode(target, state, changes) do
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
    with :ok <- Channel.privmsg(target, state, message) do
      {:ok, state}
    end
  end

  def execute(state, {:send_user_notice, target, message}) do
    Client.notice(target, state, message)
    {:ok, state}
  end

  def execute(state, {:send_channel_notice, target, message}) do
    Channel.notice(target, state, message)
    {:ok, state}
  end

  defp do_join(channel_name, key, state) do
    case Channel.join(channel_name, state, key) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:no_such_channel, _channel_name}} ->
        case DynamicSupervisor.start_child(ChannelSupervisor, {Channel, name: channel_name}) do
          {:ok, pid} ->
            Channel.join(pid, state, key)

          {:error, {:already_started, pid}} ->
            Channel.join(pid, state, key)

          error ->
            Logger.warning("Failed to create channel #{channel_name}: #{inspect(error)}")
            error
        end

      error ->
        error
    end
  end
end
