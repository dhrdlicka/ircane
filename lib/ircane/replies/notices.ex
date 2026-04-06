defmodule IRCane.Replies.Notices do
  alias IRCane.Protocol.Message

  @server_name Application.compile_env(:ircane, :server_name)

  def format(:rdns_in_progress, client),
    do: notice("*** Looking up your hostname...", client)

  def format({:rdns_successful, hostname}, client),
    do: notice("*** Found your hostname: #{hostname}", client)

  def format({:rdns_failed, hostname}, client),
    do:
      notice(
        "*** Could not resolve your hostname; using your IP address (#{hostname}) instead",
        client
      )

  def format({:unknown_message, message}, client),
    do: notice("*** Unknown message: #{inspect(message)}", client)

  def format(_other, _client), do: nil

  defp notice(message, client) do
    target = client.nickname || "*"

    %Message{
      source: @server_name,
      command: "NOTICE",
      params: [target, message]
    }
  end
end
