defmodule IRCane.Command.Effects do
  @moduledoc false

  alias IRCane.Channel
  alias IRCane.User.State, as: UserState

  require Logger

  @type effect ::
          {:register_nickname, String.t() | nil}
          | {:broadcast_nickname_change, UserState.t()}

  @spec execute(UserState.t(), effect()) ::
          {:ok, UserState.t()} | {:ok, UserState.t(), [term()]} | {:error, term()}
  def execute(state, {:register_nickname, old_nickname}) do
    new_key = String.downcase(state.nickname)

    case Registry.register(IRCane.UserRegistry, new_key, UserState.metadata(state)) do
      {:ok, _} ->
        if not is_nil(old_nickname) do
          old_key = String.downcase(old_nickname)
          Registry.unregister(IRCane.UserRegistry, old_key)
        end

        {:ok, state}

      {:error, {:already_registered, pid}} when pid == self() ->
        {:ok, state}

      {:error, {:already_registered, _}} ->
        Logger.debug("Nickname #{state.nickname} already in use")
        {:error, {:nickname_in_use, state.nickname}}
    end
  end

  def execute(state, {:broadcast_nickname_change, old_state}) do
    if state.nickname != old_state.nickname do
      ref = make_ref()

      state.channels
      |> Map.keys()
      |> Enum.each(&Channel.broadcast_nick(&1, ref, old_state, state.nickname))
    end

    {:ok, state}
  end
end
