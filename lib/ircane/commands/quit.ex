defmodule IRCane.Commands.Quit do
  alias IRCane.User.State, as: UserState

  require Logger

  def handle(params, state) do
    quit_message = "Quit: " <> Enum.join(params, " ")
    Logger.notice("User #{state.nickname} quit: #{quit_message}")

    {:ok, UserState.quit(state, quit_message)}
  end
end
