defmodule IRCane.Replies do
  alias IRCane.Channel.Topic
  alias IRCane.Protocol.Message
  alias IRCane.Protocol.Mode
  alias IRCane.Replies.Notices
  alias IRCane.Replies.Numerics
  alias IRCane.User.State, as: UserState
  alias IRCane.Utils.ISupport

  @server_name Application.compile_env(:ircane, :server_name)
  @channel_modes Application.compile_env(:ircane, :channel_modes)

  def format({:nick, source, new_nickname}, _client),
    do: message(source, "NICK", [new_nickname])

  def format({:ping, token}, _client),
    do: message(nil, "PING", [token])

  def format({:pong, token}, _client),
    do: message(:server, "PONG", [@server_name, token])

  def format({:quit, source, quit_message}, _client),
    do: message(source, "QUIT", [quit_message])

  def format({:error, reason}, _client),
    do: message(nil, "ERROR", [reason])

  def format({:join, source, channel_name}, _client),
    do: message(source, "JOIN", [channel_name])

  def format({:part, source, channel_name, part_message}, _client),
    do: message(source, "PART", [channel_name, part_message])

  def format({:topic, source, channel_name, topic}, _client),
    do: message(source, "TOPIC", [channel_name, topic])

  def format({:topic, channel_name, %Topic{} = topic}, client) do
    [
      numeric({:topic, channel_name, topic.topic}, client),
      numeric({:topic_who_time, channel_name, topic.set_by, topic.set_at}, client)
    ]
  end

  def format({:names, channel_name, status, nicknames}, client) do
    nicknames
    |> Enum.chunk_every(10)
    |> Enum.map(&numeric({:names_reply, channel_name, status, &1}, client))
    |> List.insert_at(-1, numeric({:end_of_names, channel_name}, client))
  end

  def format({:kick, source, channel, user, comment}, _client),
    do: message(source, "KICK", [channel, user, comment])

  def format({:lusers, lusers}, client) do
    [
      numeric({:luser_client, lusers.users, lusers.invisible, lusers.servers}, client),
      numeric({:luser_op, lusers.operators}, client),
      numeric({:luser_unknown, lusers.unknown}, client),
      numeric({:luser_channels, lusers.channels}, client),
      numeric({:luser_me, lusers.users, lusers.servers}, client),
      numeric({:local_users, lusers.users, lusers.max_users}, client),
      numeric({:global_users, lusers.users, lusers.max_users}, client)
    ]
  end

  def format({:channel_mode, source, channel, modes}, _client) do
    mode_strings = Mode.format(modes, @channel_modes)
    message(source, "MODE", [channel | mode_strings])
  end

  def format({:privmsg, source, target, message}, _client),
    do: message(source, "PRIVMSG", [target, message])

  def format({:notice, source, target, message}, _client),
    do: message(source, "NOTICE", [target, message])

  def format(:i_support, client) do
    ISupport.build()
    |> Enum.chunk_every(13)
    |> Enum.map(&numeric({:i_support, &1}, client))
  end

  def format(reply, client) do
    numeric(reply, client) || notice(reply, client) || format({:unknown_message, reply}, client)
  end

  defp message(:server, command, params) do
    %Message{source: @server_name, command: command, params: params}
  end

  defp message(%UserState{} = source, command, params) do
    %Message{
      source: {source.nickname, source.username, source.hostname},
      command: command,
      params: params
    }
  end

  defp message(source, command, params) do
    %Message{source: source, command: command, params: params}
  end

  defp numeric(reply, client), do: Numerics.format(reply, client)
  defp notice(reply, client), do: Notices.format(reply, client)
end
