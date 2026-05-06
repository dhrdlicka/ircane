defmodule IRCane.Command.Handler do
  @moduledoc false

  alias IRCane.Command.Plan
  alias IRCane.User.State, as: UserState

  @callback handle(params :: [String.t()], user_state :: UserState.t()) ::
              {:ok, Plan.t()} | {:error, term()}
end
