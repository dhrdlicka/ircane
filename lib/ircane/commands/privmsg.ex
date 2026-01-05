defmodule IRCane.Commands.Privmsg do
  alias IRCane.Channel
  alias IRCane.ChannelRegistry
  alias IRCane.Client
  alias IRCane.NickRegistry

  require Logger

  def handle([targets, message | message_parts], state) do
    message = Enum.join([message | message_parts], " ")

    targets
    |> String.split(",")
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.map(&dispatch(&1, message, state))
    |> Enum.reject(&(&1 == :ok))
    |> case do
      [] ->
        {:ok, state}

      errors ->
        Logger.debug("PRIVMSG errors from #{state.nickname}: #{inspect(errors)}")
        {:error, Enum.map(errors, &elem(&1, 1))}
    end
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "PRIVMSG"}}
  end

  defp dispatch("#" <> _ = target, message, state) do
    with [{pid, _}] <- Registry.lookup(ChannelRegistry, String.downcase(target)) do
      Channel.privmsg(pid, state, message)
    else
      [] ->
        {:error, {:no_such_nick, target}}
    end
  end

  defp dispatch(target, message, state) do
    with [{pid, _}] <- Registry.lookup(NickRegistry, String.downcase(target)) do
      Client.privmsg(pid, state, message)
    else
      [] ->
        {:error, {:no_such_nick, target}}
    end
  end
end
