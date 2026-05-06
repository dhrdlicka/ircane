defmodule IRCane.Commands.Join do
  @moduledoc false

  alias IRCane.Command.Plan

  require Logger

  @behaviour IRCane.Command.Handler

  def handle(["0"], state) do
    effects =
      Enum.map(state.channels, fn {_pid, %{name: channel_name}} ->
        {:part_channel, channel_name, ""}
      end)

    state
    |> Plan.new()
    |> Plan.with_effects(effects)
    |> then(&{:ok, &1})
  end

  def handle([channels | keys], state) do
    effects =
      channels
      |> String.split(",")
      |> zip_fill(keys)
      |> Enum.map(fn {channel_name, key} -> {:join_channel, channel_name, key} end)

    state
    |> Plan.new()
    |> Plan.with_effects(effects)
    |> then(&{:ok, &1})
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "JOIN"}}
  end

  defp zip_fill([x | xs], [y | ys]), do: [{x, y} | zip_fill(xs, ys)]
  defp zip_fill(xs, []), do: Enum.map(xs, &{&1, nil})
  defp zip_fill([], _), do: []
end
