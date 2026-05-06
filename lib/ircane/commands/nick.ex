defmodule IRCane.Commands.Nick do
  @moduledoc false

  alias IRCane.Command.Plan
  alias IRCane.User.State, as: UserState

  require Logger

  @behaviour IRCane.Command.Handler

  def handle([new_nickname | _], state) do
    with {:ok, new_state} <- UserState.update_nickname(state, new_nickname) do
      base_plan =
        new_state
        |> Plan.new()
        |> Plan.with_effect({:register_nickname, state.nickname})

      if state.registered? do
        base_plan
        |> Plan.with_effect({:broadcast_nickname_change, state})
        |> Plan.with_reply({:nick, state.nickname, new_nickname})
        |> then(&{:ok, &1})
      else
        {:ok, base_plan}
      end
    end
  end

  def handle(_params, _state) do
    {:error, :no_nickname_given}
  end
end
