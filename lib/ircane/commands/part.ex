defmodule IRCane.Commands.Part do
  alias IRCane.Channel

  def handle([channels | rest], state) do
    reason = Enum.join(rest, " ")

    channels
    |> String.split(",")
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.reduce({[], state}, fn channel_name, {replies, current_state} ->
      case part_channel(channel_name, state, reason) do
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
    {:error, {:need_more_params, "PART"}}
  end

  defp part_channel(channel_name, state, reason) do
    with {:ok, channel_pid} <- Channel.part(channel_name, state, reason) do
      new_state = %{state | joined_channels: MapSet.delete(state.joined_channels, channel_pid)}
      {:ok, {:part, state, channel_name, reason}, new_state}
    end
  end
end
