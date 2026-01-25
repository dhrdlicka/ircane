defmodule IRCane.Commands.Nick do
  alias IRCane.Channel

  require Logger

  def handle(["#" <> _ = new_nickname | _], _state) do
    {:error, {:erroneous_nickname, new_nickname}}
  end

  def handle([":" <> _ = new_nickname | _], _state) do
    {:error, {:erroneous_nickname, new_nickname}}
  end

  def handle([new_nickname | _], state) do
    new_key = String.downcase(new_nickname)
    old_key = String.downcase(state.nickname || "")

    with {:ok, _} <- Registry.register(IRCane.UserRegistry, new_key, new_nickname) do
      Registry.unregister(IRCane.UserRegistry, old_key)

      new_state = %{state | nickname: new_nickname}

      if state.registered? do
        Logger.notice("User changed nickname: #{state.nickname} -> #{new_nickname}")

        ref = make_ref()
        Enum.each(state.joined_channels, &Channel.broadcast_nick(&1, ref, state, new_nickname))

        new_state = %{state | nickname: new_nickname}
        {:ok, {:nick, state, new_nickname}, new_state}
      else
        {:ok, new_state}
      end

    else
      {:error, {:already_registered, _}} ->
        Logger.debug("Nickname #{new_nickname} already in use")
        {:error, {:nickname_in_use, new_nickname}}
    end
  end

  def handle(_, _state) do
    {:error, :no_nickname_given}
  end
end
