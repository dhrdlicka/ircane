defmodule IRCane.Commands.Part do
  alias IRCane.Channel
  alias IRCane.User.State, as: UserState

  def handle([channels | rest], state) do
    reason = Enum.join(rest, " ")

    channels
    |> String.split(",")
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.reduce({[], state}, fn channel_name, {replies, current_state} ->
      case part_channel(channel_name, current_state, reason) do
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
      {%{monitor_ref: ref}, new_state} = UserState.pop_channel(state, channel_pid)
      Process.demonitor(ref)

      {:ok, {:part, state, channel_name, reason}, new_state}
    end
  end
end
