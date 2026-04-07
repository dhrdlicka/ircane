defmodule IRCane.Commands.Notice do
  @moduledoc false
  alias IRCane.Channel
  alias IRCane.Client

  def handle([targets, message | message_parts], state) do
    message = Enum.join([message | message_parts], " ")

    targets
    |> String.split(",")
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.each(&dispatch(&1, message, state))

    {:ok, state}
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "NOTICE"}}
  end

  defp dispatch("#" <> _ = target, message, state) do
    Channel.notice(target, state, message)
    :ok
  end

  defp dispatch(target, message, state) do
    Client.notice(target, state, message)
    :ok
  end
end
