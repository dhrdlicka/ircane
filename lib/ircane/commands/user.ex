defmodule IRCane.Commands.User do
  require Logger

  def handle(_, %{registered?: true} = _state) do
    {:error, :already_registered}
  end

  def handle([username, _, _, realname | _], state) do
    Logger.debug("User set username: #{username}, realname: #{realname}")
    {:ok, %{state | username: username, realname: realname}}
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "USER"}}
  end
end
