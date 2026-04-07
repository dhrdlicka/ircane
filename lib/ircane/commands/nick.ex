defmodule IRCane.Commands.Nick do
  @moduledoc false
  alias IRCane.Channel
  alias IRCane.User.State, as: UserState

  require Logger

  def handle([new_nickname | _], state) do
    with {:ok, new_state} <- UserState.update_nickname(state, new_nickname),
         :ok <- update_registration(state.nickname, new_nickname) do
      if state.registered? do
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

  def update_registration(old_nickname, new_nickname) do
    new_key = String.downcase(new_nickname)

    case Registry.register(IRCane.UserRegistry, new_key, new_nickname) do
      {:ok, _} ->
        if not is_nil(old_nickname) do
          old_key = String.downcase(old_nickname)
          Registry.unregister(IRCane.UserRegistry, old_key)
        end

        :ok

      {:error, {:already_registered, _}} ->
        Logger.debug("Nickname #{new_nickname} already in use")
        {:error, {:nickname_in_use, new_nickname}}
    end
  end
end
