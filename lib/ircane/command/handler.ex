defmodule IRCane.Command.Handler do
  @moduledoc false

  alias IRCane.User.State, as: UserState
  alias IRCane.Command.Plan

  @callback handle(params :: [String.t()], user_state :: UserState.t()) ::
              {:ok, Plan.t()} | {:error, term()}
end
