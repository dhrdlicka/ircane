defmodule IRCane.Commands.Names do
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
    case Channel.names(channel_name) do
      {:ok, {channel_name, names}} ->
        {:names, channel_name, :public, names}

      _ ->
        {:names, channel_name, :public, []}
    end
  end
end
