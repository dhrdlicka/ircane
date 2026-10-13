defmodule IRCane.Client.Command.Handlers.Quit do
  @moduledoc false

  alias IRCane.Client.Command.Plan

  require Logger

  @behaviour IRCane.Client.Command.Handler

  def handle(params, state) do
    quit_message = "Quit: " <> Enum.join(params, " ")

    plan =
      state
      |> Plan.new()
      |> Plan.with_stop({:quit, quit_message})

    {:ok, plan}
  end
end
