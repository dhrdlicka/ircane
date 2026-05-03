defmodule IRCane.Command.Dispatcher do
  @moduledoc false

  alias IRCane.User.State, as: UserState
  alias IRCane.Command.Plan

  require Logger

  @command_handlers %{}
  @unregistered_commands ["PASS", "NICK", "USER"]

  @spec dispatch(String.t(), [String.t()], UserState.t()) :: {:ok, Plan.t()} | {:error, term()}
  def dispatch(command, _params, %{registered?: false} = _user_state)
      when command not in @unregistered_commands do
    {:error, :not_registered}
  end

  def dispatch(command, params, user_state) do
    case Map.get(@command_handlers, command) do
      nil ->
        Logger.debug("Unknown command from #{client_id(user_state)}: #{command}")
        {:error, {:unknown_command, command}}

      handler ->
        handler.handle(params, user_state)
    end
  end

  defp client_id(%{user: user}), do: client_id(user)

  defp client_id(user) do
    user.nickname || host_mask(user)
  end

  defp host_mask(%{user: user}), do: host_mask(user)

  defp host_mask(user) do
    "#{user.username || "unknown"}@#{user.hostname || "unknown"}"
  end
end
