defmodule IRCane.Commands.User do
  @moduledoc false

  alias IRCane.Command.Plan
  alias IRCane.User.State, as: UserState

  require Logger

  @behaviour IRCane.Command.Handler

  def handle(_, %{registered?: true} = _state) do
    {:error, :already_registered}
  end

  def handle([username, _, _, realname | _], state) do
    with {:ok, new_state} <- UserState.update_username(state, username) do
      Logger.debug("User set username: #{username}, realname: #{realname}")
      {:ok, new_state |> UserState.update_realname(realname) |> Plan.new()}
    end
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "USER"}}
  end
end
