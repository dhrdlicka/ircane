defmodule IRCane.Commands.Names do
  alias IRCane.Channel
  alias IRCane.ChannelRegistry

  def handle([channels | _], state) do
    names =
      channels
      |> String.split(",")
      |> Enum.uniq_by(&String.downcase/1)
      |> Enum.map(&fetch_names/1)

    {:ok, names, state}
  end

  def handle([], _state) do
    {:error, {:need_more_params, "NAMES"}}
  end

  defp fetch_names(channel_name) do
    case Registry.lookup(ChannelRegistry, String.downcase(channel_name)) do
      [{pid, _}] ->
        with {:ok, {channel_name, names}} <- Channel.names(pid),
          do: {:names, channel_name, names}
      [] ->
        {:names, channel_name, []}
    end
  end
end
