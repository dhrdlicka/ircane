defmodule IRCane.Client.Command.Handlers.Names do
  @moduledoc false

  alias IRCane.Client.Command.Plan

  @behaviour IRCane.Client.Command.Handler

  def handle([channels | _], state) do
    unique_channels =
      channels
      |> String.split(",")
      |> Enum.uniq_by(&String.downcase/1)

    state
    |> Plan.new()
    |> Plan.with_effects(Enum.map(unique_channels, &{:get_channel_names, &1}))
    |> then(&{:ok, &1})
  end

  def handle([], _state) do
    {:error, {:need_more_params, "NAMES"}}
  end
end
