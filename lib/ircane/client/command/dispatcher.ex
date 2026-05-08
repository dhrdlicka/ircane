defmodule IRCane.Client.Command.Dispatcher do
  @moduledoc false

  alias IRCane.Client.Command.Plan
  alias IRCane.Protocol.Message
  alias IRCane.Replies
  alias IRCane.User.State, as: UserState

  require Logger

  @command_handlers %{
    "NICK" => IRCane.Client.Command.Handlers.Nick,
    "PING" => IRCane.Client.Command.Handlers.Ping,
    "PONG" => IRCane.Client.Command.Handlers.Pong,
    "USER" => IRCane.Client.Command.Handlers.User,
    "MOTD" => IRCane.Client.Command.Handlers.Motd,
    "LUSERS" => IRCane.Client.Command.Handlers.Lusers,
    "PRIVMSG" => IRCane.Client.Command.Handlers.Privmsg,
    "NOTICE" => IRCane.Client.Command.Handlers.Notice,
    "JOIN" => IRCane.Client.Command.Handlers.Join,
    "PART" => IRCane.Client.Command.Handlers.Part,
    "NAMES" => IRCane.Client.Command.Handlers.Names,
    "TOPIC" => IRCane.Client.Command.Handlers.Topic,
    "MODE" => IRCane.Client.Command.Handlers.Mode,
    "QUIT" => IRCane.Client.Command.Handlers.Quit
  }
  @unregistered_commands ["PASS", "NICK", "USER"]

  @spec dispatch(Message.t(), UserState.t()) :: {:ok, Plan.t()} | {:error, Replies.reply()}
  def dispatch(%Message{command: command, params: params}, user_state) do
    command
    |> String.upcase()
    |> do_dispatch(params, user_state)
  end

  defp do_dispatch(command, _params, %{registered?: false} = _user_state)
       when command not in @unregistered_commands do
    {:error, :not_registered}
  end

  defp do_dispatch(command, params, user_state) do
    case Map.get(@command_handlers, String.upcase(command)) do
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
