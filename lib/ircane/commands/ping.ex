defmodule IRCane.Commands.Ping do
  def handle([token | _], state) do
    {:ok, {:pong, token}, state}
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "PING"}}
  end
end
