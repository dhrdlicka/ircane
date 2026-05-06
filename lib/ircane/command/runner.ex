defmodule IRCane.Command.Runner do
  @moduledoc false

  alias IRCane.Command.Plan
  alias IRCane.User.State, as: UserState

  @spec run(Plan.t()) :: {:ok, [term()], UserState.t()} | {:error, term()}
  def run(%Plan{effects: []} = plan) do
    {:ok, plan.replies, plan.state}
  end
end
