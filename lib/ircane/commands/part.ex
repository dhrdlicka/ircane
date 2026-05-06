defmodule IRCane.Commands.Part do
  @moduledoc false

  alias IRCane.Command.Plan

  @behaviour IRCane.Command.Handler

  def handle([channels | rest], state) do
    reason = Enum.join(rest, " ")

    effects =
      channels
      |> String.split(",")
      |> Enum.uniq_by(&String.downcase/1)
      |> Enum.map(&{:part_channel, &1, reason})

    state
    |> Plan.new()
    |> Plan.with_effects(effects)
    |> then(&{:ok, &1})
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "PART"}}
  end
end
