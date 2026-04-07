defmodule IRCane.Commands.User do
  @moduledoc false
  alias IRCane.User.State, as: UserState
  require Logger

  def handle(_, %{registered?: true} = _state) do
    {:error, :already_registered}
  end

  def handle([username, _, _, realname | _], state) do
    with {:ok, new_state} <- UserState.update_username(state, username) do
      Logger.debug("User set username: #{username}, realname: #{realname}")
      {:ok, UserState.update_realname(new_state, realname)}
    end
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "USER"}}
  end
end
