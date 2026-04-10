defmodule IRCane.Commands.Names do
  @moduledoc false
  alias IRCane.Channel

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
    {channel_name, status, names} = Channel.names(channel_name)
    {:names, channel_name, status, names}
  end
end
