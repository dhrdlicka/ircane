defmodule IRCane.Channels do
  @moduledoc false

  alias IRCane.Channel
  alias IRCane.Channel.Membership
  alias IRCane.Channel.Topic
  alias IRCane.ChannelSupervisor
  alias IRCane.Protocol.Mode
  alias IRCane.User.State, as: UserState
  alias IRCane.Utils

  require Logger

  @max_join_attempts 3

  @spec join(String.t(), UserState.t(), String.t() | nil) ::
          {:ok, pid()} | :noop | {:error, term()}
  def join(channel_name, client, key) do
    if Utils.valid_channel_name?(channel_name) do
      join(channel_name, client, key, @max_join_attempts)
    else
      {:error, {:bad_chan_mask, channel_name}}
    end
  end

  defp join(channel_name, _client, _key, 0) do
    {:error, {:unavail_resource, channel_name}}
  end

  defp join(channel_name, client, key, attempts) do
    case safe_call(channel_name, &Channel.request(&1, client, {:join, key})) do
      {:error, {:no_such_channel, _channel}} ->
        case DynamicSupervisor.start_child(ChannelSupervisor, {Channel, name: channel_name}) do
          {:ok, _pid} ->
            join(channel_name, client, key, attempts - 1)

          {:error, {:already_started, _pid}} ->
            join(channel_name, client, key, attempts - 1)

          error ->
            Logger.warning("Failed to create channel #{channel_name}: #{inspect(error)}")
            {:error, {:unavail_resource, channel_name}}
        end

      result ->
        result
    end
  end

  @spec part(String.t(), UserState.t(), String.t()) :: {:ok, pid()} | {:error, term()}
  def part(channel_name, client, reason),
    do: safe_call(channel_name, &Channel.request(&1, client, {:part, reason}))

  @spec names(String.t(), UserState.t()) ::
          {String.t(), pid() | nil, :public | :secret | :none, [Membership.t()]}
  def names(channel_name, client) do
    with {:error, _} <- safe_call(channel_name, &Channel.request(&1, client, :names)) do
      {channel_name, nil, :none, []}
    end
  end

  @spec privmsg(String.t(), UserState.t(), String.t()) :: :ok | {:error, term()}
  def privmsg(channel_name, client, message),
    do: safe_call(channel_name, &Channel.request(&1, client, {:privmsg, message}))

  @spec notice(String.t(), UserState.t(), String.t()) :: :ok
  def notice(channel_name, client, message) do
    safe_call(channel_name, &Channel.request(&1, client, {:notice, message}))
    :ok
  end

  @spec topic(String.t(), UserState.t()) ::
          {:ok, {String.t(), Topic.t() | nil}} | {:error, term()}
  def topic(channel_name, client),
    do: safe_call(channel_name, &Channel.request(&1, client, :topic))

  @spec update_topic(String.t(), UserState.t(), String.t()) :: :ok | {:error, term()}
  def update_topic(channel_name, client, new_topic),
    do: safe_call(channel_name, &Channel.request(&1, client, {:update_topic, new_topic}))

  @spec mode(String.t(), UserState.t()) :: {:ok, {String.t(), [Mode.t()]}} | {:error, term()}
  def mode(channel_name, client), do: safe_call(channel_name, &Channel.request(&1, client, :mode))

  @spec update_mode(String.t(), UserState.t(), [Mode.mode_change()]) ::
          {:ok, {String.t(), [Mode.mode_change()], [atom()]}} | {:error, term()}
  def update_mode(channel_name, client, mode_changes),
    do: safe_call(channel_name, &Channel.request(&1, client, {:update_mode, mode_changes}))

  @spec broadcast_nick(pid(), reference(), UserState.t(), String.t()) :: :ok
  def broadcast_nick(channel_pid, ref, client, new_nick),
    do: Channel.broadcast_nick(channel_pid, ref, client, new_nick)

  defp safe_call(channel_name, fun) do
    channel_name
    |> Channel.via()
    |> fun.()
  catch
    :exit, {reason, _} when reason in [:noproc, :normal, :shutdown] ->
      {:error, {:no_such_channel, channel_name}}

    :exit, reason ->
      Logger.warning("Call to channel #{inspect(channel_name)} failed: #{inspect(reason)}")
      {:error, {:unavail_resource, channel_name}}
  end
end
