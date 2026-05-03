defmodule IRCane.Command.Runner do
  @moduledoc false

  alias IRCane.Command.Plan
  alias IRCane.User.State, as: UserState

  @spec run(Plan.t()) :: {:ok, UserState.t(), [term()]} | {:error, term()}
  def run(plan) do
    {:ok, plan.state, plan.replies}
  end
end
