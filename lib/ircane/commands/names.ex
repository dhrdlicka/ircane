defmodule IRCane.Commands.Names do
  @moduledoc false
  alias IRCane.Channel

  def handle([channels | _], state) do
    names =
      channels
      |> String.split(",")
      |> Enum.uniq_by(&String.downcase/1)
      |> Enum.map(&fetch_names(&1, state))

    {:ok, names, state}
  end

  def handle([], _state) do
    {:error, {:need_more_params, "NAMES"}}
  end

  defp fetch_names(channel_name, state) do
    {channel_name, channel_pid, status, names} = Channel.names(channel_name)

    names =
      if Map.has_key?(state.channels, channel_pid),
        do: names,
        else: Enum.filter(names, &user_visible?/1)

    {:names, channel_name, status, names}
  end

  defp user_visible?(nickname) do
    case Registry.lookup(IRCane.UserRegistry, String.downcase(nickname)) do
      [{_, %{invisible?: invisible?}}] -> not invisible?
      [] -> false
    end
  end
end
