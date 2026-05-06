defmodule IRCane.Commands.Pong do
  @moduledoc false

  alias IRCane.Command.Plan

  @behaviour IRCane.Command.Handler

  def handle([_token | _], state) do
    {:ok, Plan.new(state)}
  end

  def handle(_, _state) do
    {:error, :need_more_params}
  end
end
