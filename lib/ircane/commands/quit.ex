defmodule IRCane.Commands.Quit do
  require Logger

  def handle(params, state) do
    quit_message = "Quit :" <> Enum.join(params, " ")
    Logger.notice("User #{state.nickname} quit: #{quit_message}")

    {:ok, %{state | quit_message: quit_message, disconnecting?: true}}
  end
end
