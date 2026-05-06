defmodule IRCane.Command.Dispatcher do
  @moduledoc false

  alias IRCane.Command.Plan
  alias IRCane.Replies
  alias IRCane.User.State, as: UserState

  require Logger

  @command_handlers %{
    "NICK" => IRCane.Commands.Nick,
    "PING" => IRCane.Commands.Ping,
    "PONG" => IRCane.Commands.Pong,
    "USER" => IRCane.Commands.User,
    "MOTD" => IRCane.Commands.Motd,
    "LUSERS" => IRCane.Commands.Lusers,
    "PRIVMSG" => IRCane.Commands.Privmsg,
    "NOTICE" => IRCane.Commands.Notice,
    "JOIN" => IRCane.Commands.Join,
    "PART" => IRCane.Commands.Part,
    "NAMES" => IRCane.Commands.Names,
    "TOPIC" => IRCane.Commands.Topic,
    "MODE" => IRCane.Commands.Mode,
    "QUIT" => IRCane.Commands.Quit
  }
  @unregistered_commands ["PASS", "NICK", "USER"]

  @spec dispatch(String.t(), [String.t()], UserState.t()) ::
          {:ok, Plan.t()} | {:error, Replies.reply()}
  def dispatch(command, _params, %{registered?: false} = _user_state)
      when command not in @unregistered_commands do
    {:error, :not_registered}
  end

  def dispatch(command, params, user_state) do
    case Map.get(@command_handlers, String.upcase(command)) do
      nil ->
        Logger.debug("Unknown command from #{client_id(user_state)}: #{command}")
        {:error, {:unknown_command, command}}

      handler ->
        params
        |> handler.handle(user_state)
        |> maybe_convert_legacy_to_plan()
    end
  end

  defp maybe_convert_legacy_to_plan({:ok, %UserState{} = state}), do: {:ok, Plan.new(state)}

  defp maybe_convert_legacy_to_plan({:ok, replies, %UserState{} = state}),
    do: {:ok, Plan.new(state) |> Plan.with_replies(replies)}

  defp maybe_convert_legacy_to_plan(other), do: other

  defp client_id(%{user: user}), do: client_id(user)

  defp client_id(user) do
    user.nickname || host_mask(user)
  end

  defp host_mask(%{user: user}), do: host_mask(user)

  defp host_mask(user) do
    "#{user.username || "unknown"}@#{user.hostname || "unknown"}"
  end
end
