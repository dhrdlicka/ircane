defmodule IRCane.Commands.Nick do
  @moduledoc false
  alias IRCane.Channel
  alias IRCane.User.State, as: UserState

  require Logger

  def handle([new_nickname | _], state) do
    with {:ok, new_state} <- UserState.update_nickname(state, new_nickname),
         :ok <- update_registration(new_state, state.nickname) do
      if state.registered? and state.nickname != new_nickname do
        Logger.notice("User changed nickname: #{state.nickname} -> #{new_nickname}")

        ref = make_ref()

        state.channels
        |> Map.keys()
        |> Enum.each(&Channel.broadcast_nick(&1, ref, state, new_nickname))

        {:ok, {:nick, state, new_nickname}, new_state}
      else
        {:ok, new_state}
      end
    end
  end

  def handle(_, _state) do
    {:error, :no_nickname_given}
  end

  def update_registration(state, old_nickname) do
    new_key = String.downcase(state.nickname)

    case Registry.register(IRCane.UserRegistry, new_key, UserState.metadata(state)) do
      {:ok, _} ->
        if not is_nil(old_nickname) do
          old_key = String.downcase(old_nickname)
          Registry.unregister(IRCane.UserRegistry, old_key)
        end

        :ok

      {:error, {:already_registered, pid}} when pid == self() ->
        :ok

      {:error, {:already_registered, _}} ->
        Logger.debug("Nickname #{state.nickname} already in use")
        {:error, {:nickname_in_use, state.nickname}}
    end
  end
end
