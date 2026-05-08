defmodule IRCane.Client.Command.Handlers.Quit do
  @moduledoc false

  alias IRCane.Client.Command.Plan
  alias IRCane.User.State, as: UserState

  require Logger

  @behaviour IRCane.Client.Command.Handler

  def handle(params, state) do
    quit_message = "Quit: " <> Enum.join(params, " ")

    plan =
      state
      |> UserState.quit(quit_message)
      |> Plan.new()
      |> Plan.with_reply({:quit, quit_message})

    {:ok, plan}
  end
end
