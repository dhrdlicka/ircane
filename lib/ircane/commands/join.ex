defmodule IRCane.Commands.Join do
  alias IRCane.Channel
  alias IRCane.ChannelSupervisor

  require Logger

  @max_join_attempts 3

  def handle([channels | keys], state) do
    channels
    |> String.split(",")
    |> zip_fill(keys)
    |> Enum.reduce({[], state}, fn {channel_name, key}, {replies, current_state} ->
      case join_channel(channel_name, key, current_state) do
        {:ok, new_state} ->
          {replies, new_state}

        {:ok, reply, new_state} ->
          {[reply | replies], new_state}

        {:error, reason} ->
          {[reason | replies], current_state}
      end
    end)
    |> then(fn {replies, final_state} -> {:ok, replies, final_state} end)
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "JOIN"}}
  end

  defp join_channel(channel_name, key, state) do
    with :ok <- validate_channel_name(channel_name),
         {:ok, channel_pid} <- do_join(channel_name, key, state),
         {:ok, {channel_name, topic}} <- Channel.topic(channel_pid),
         {:ok, {_channel_name, names}} <- Channel.names(channel_pid) do
      channel_info = %{
        name: channel_name,
        monitor_ref: Process.monitor(channel_pid)
      }

      new_state = %{
        state
        | joined_channels: Map.put(state.joined_channels, channel_pid, channel_info)
      }

      reply =
        if topic do
          [
            {:join, state, channel_name},
            {:topic, channel_name, topic},
            {:names, channel_name, names}
          ]
        else
          [
            {:join, state, channel_name},
            {:names, channel_name, names}
          ]
        end

      {:ok, reply, new_state}
    else
      :noop ->
        {:ok, state}

      error ->
        error
    end
  end

  defp validate_channel_name("#" <> _ = channel_name) do
    channel_name
    |> String.to_charlist()
    |> Enum.all?(fn char -> char not in ~c" ,\07" end)
    |> if do
      :ok
    else
      {:error, {:invalid_channel_name, channel_name}}
    end
  end

  defp validate_channel_name(channel_name) do
    {:error, {:invalid_channel_name, channel_name}}
  end

  defp do_join(channel_name, key, state, attempts \\ @max_join_attempts)

  defp do_join(channel_name, _key, _state, 0) do
    {:error, {:no_such_channel, channel_name}}
  end

  defp do_join(channel_name, key, state, attempts) do
    case Channel.join(channel_name, state, key) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:no_such_channel, _channel_name}} ->
        case DynamicSupervisor.start_child(ChannelSupervisor, {Channel, name: channel_name}) do
          {:ok, pid} ->
            Channel.join(pid, state, key)

          {:error, {:already_started, _pid}} ->
            do_join(channel_name, key, state, attempts - 1)

          error ->
            Logger.warning("Failed to create channel #{channel_name}: #{inspect(error)}")
            do_join(channel_name, key, state, attempts - 1)
        end

      error ->
        error
    end
  end

  defp zip_fill([x | xs], [y | ys]), do: [{x, y} | zip_fill(xs, ys)]
  defp zip_fill([x | xs], []), do: [{x, nil} | zip_fill(xs, [])]
  defp zip_fill([], _), do: []
end
