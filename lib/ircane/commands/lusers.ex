defmodule IRCane.Commands.Lusers do
  @moduledoc false

  alias IRCane.Command.Plan

  def handle(_params, state) do
    state
    |> Plan.new()
    |> Plan.with_effect(:get_lusers_stats)
    |> then(&{:ok, &1})
  end
end
