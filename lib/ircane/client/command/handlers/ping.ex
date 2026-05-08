defmodule IRCane.Client.Command.Handlers.Ping do
  @moduledoc false

  alias IRCane.Client.Command.Plan

  @behaviour IRCane.Client.Command.Handler

  def handle([token | _], state) do
    {:ok, state |> Plan.new() |> Plan.with_reply({:pong, token})}
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "PING"}}
  end
end
