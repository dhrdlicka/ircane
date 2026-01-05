defmodule IRCane.Commands.Notice do
  alias IRCane.Channel
  alias IRCane.ChannelRegistry
  alias IRCane.Client
  alias IRCane.NickRegistry

  def handle([targets, message | message_parts], state) do
    message = Enum.join([message | message_parts], " ")

    targets
    |> String.split(",")
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.map(&dispatch(&1, message, state))

    {:ok, state}
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "NOTICE"}}
  end

  defp dispatch("#" <> _ = target,  message, state) do
    with [{pid, _}] <- Registry.lookup(ChannelRegistry, String.downcase(target)) do
      Channel.notice(pid, state, message)
    end
  end

  defp dispatch(target,  message, state) do
    with [{pid, _}] <- Registry.lookup(NickRegistry, String.downcase(target)) do
      Client.notice(pid, state, message)
    end
  end
end
