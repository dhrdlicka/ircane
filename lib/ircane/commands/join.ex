defmodule IRCane.Commands.Join do
  alias IRCane.Channel
  alias IRCane.ChannelRegistry
  alias IRCane.ChannelSupervisor

  require Logger

  def handle([channels | _], state) do
    channels
    |> String.split(",")
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.reduce({[], state}, fn channel_name, {replies, current_state} ->
      case join_channel(channel_name, current_state) do
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

  defp join_channel(channel_name, state) do
    with :ok <- validate_channel_name(channel_name),
         {:ok, channel_pid} <- ensure_channel(channel_name),
         :ok <- Channel.join(channel_pid, state),
         {:ok, {channel_name, topic}} <- Channel.topic(channel_pid),
         {:ok, {_channel_name, names}} <- Channel.names(channel_pid) do
      new_state = %{state | joined_channels: MapSet.put(state.joined_channels, channel_pid)}

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

  defp ensure_channel(channel_name) do
    case Registry.lookup(ChannelRegistry, String.downcase(channel_name)) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(ChannelSupervisor, {Channel, name: channel_name}) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            # Race condition: channel was created between our lookup and start
            Logger.debug("Channel #{channel_name} race condition detected, joining existing channel")
            {:ok, pid}

          error ->
            Logger.warning("Failed to create channel #{channel_name}: #{inspect(error)}")
            error
        end
    end
  end
end
