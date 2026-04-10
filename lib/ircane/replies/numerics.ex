defmodule IRCane.Replies.Numerics do
  @moduledoc false
  alias IRCane.BanMask
  alias IRCane.Channel.Role
  alias IRCane.Protocol.Message
  alias IRCane.Protocol.Mode
  alias IRCane.Stats

  @server_name Application.compile_env(:ircane, :server_name)
  @network_name Application.compile_env(:ircane, :network_name)
  @version Application.compile_env(:ircane, :version)
  @user_modes Application.compile_env(:ircane, :user_modes)
  @channel_modes Application.compile_env!(:ircane, :channel_modes)

  def format(:welcome, client),
    do: numeric(001, client, "Welcome to the #{@network_name} Network, #{client.nickname}")

  def format(:your_host, client),
    do: numeric(002, client, "Your host is #{@server_name}, running version #{@version}")

  def format(:created, client),
    do: numeric(003, client, "This server was created #{Stats.created_at()}")

  def format(:my_info, client) do
    user_modes =
      @user_modes
      |> Map.keys()
      |> to_string()

    channel_modes =
      @channel_modes
      |> Map.keys()
      |> to_string()

    channel_modes_with_params =
      @channel_modes
      |> Enum.filter(fn {_letter, {type, _name, _opts}} -> type != :no_param end)
      |> Enum.map(fn {letter, _} -> letter end)
      |> to_string()

    numeric(004, client, nil, [
      @server_name,
      @version,
      user_modes,
      channel_modes,
      channel_modes_with_params
    ])
  end

  def format({:i_support, features}, client) do
    tokens =
      Enum.map(features, fn
        {key, value} -> "#{key |> Atom.to_string() |> String.upcase()}=#{value}"
        token -> token |> Atom.to_string() |> String.upcase()
      end)

    numeric(005, client, "are supported by this server", tokens)
  end

  def format({:luser_client, users, invisibles, servers}, client),
    do:
      numeric(
        251,
        client,
        "There are #{users} users and #{invisibles} invisible on #{servers} servers"
      )

  def format({:luser_op, operators}, client),
    do: numeric(252, client, "operator(s) online", [to_string(operators)])

  def format({:luser_unknown, unknown}, client),
    do: numeric(253, client, "unknown connection(s)", [to_string(unknown)])

  def format({:luser_channels, channels}, client),
    do: numeric(254, client, "channels formed", [to_string(channels)])

  def format({:luser_me, clients, servers}, client),
    do: numeric(255, client, "I have #{clients} clients and #{servers} servers")

  def format({:local_users, users, max}, client),
    do:
      numeric(265, client, "Current local users: #{users}, max: #{max}", [
        to_string(users),
        to_string(max)
      ])

  def format({:global_users, users, max}, client),
    do:
      numeric(266, client, "Current global users: #{users}, max: #{max}", [
        to_string(users),
        to_string(max)
      ])

  def format({:channel_mode_is, channel, modes}, client) do
    mode_strings =
      modes
      |> Enum.map(&{:add, &1})
      |> Mode.format(@channel_modes)

    numeric(324, client, nil, [channel | mode_strings])
  end

  def format({:names_reply, channel, status, members}, client) do
    symbol =
      case status do
        :public -> "="
        :private -> "@"
        :secret -> "*"
      end

    names =
      Enum.map_join(members, " ", fn
        %{nickname: nickname, roles: roles} ->
          prefix = roles |> Role.max() |> Role.prefix()
          prefix <> nickname
      end)

    numeric(353, client, nil, [symbol, channel, names])
  end

  def format({:end_of_names, channel}, client),
    do: numeric(366, client, "End of /NAMES list", [channel])

  def format({:ban_list, channel, mask}, client),
    do: numeric(367, client, nil, [channel, BanMask.format(mask)])

  def format({:end_of_ban_list, channel}, client),
    do: numeric(368, client, "End of channel ban list", [channel])

  def format({:no_topic, channel}, client),
    do: numeric(331, client, "No topic is set", [channel])

  def format({:topic, channel, topic}, client),
    do: numeric(332, client, nil, [channel, topic])

  def format({:topic_who_time, channel, nick, set_at}, client),
    do: numeric(333, client, nil, [channel, nick, "#{DateTime.to_unix(set_at)}"])

  def format({:no_such_nick, nickname}, client),
    do: numeric(401, client, "No such nick/channel", [nickname])

  def format({:no_such_channel, channel}, client),
    do: numeric(403, client, "No such channel", [channel])

  def format({:cannot_send_to_chan, channel}, client),
    do: numeric(404, client, "Cannot send to channel", [channel])

  def format(:input_too_long, client),
    do: numeric(417, client, "Input line was too long")

  def format({:unknown_command, command}, client),
    do: numeric(421, client, "Unknown command", [command])

  def format(:no_motd, client),
    do: numeric(422, client, "MOTD File is missing")

  def format({:erroneous_nickname, nickname}, client),
    do: numeric(432, client, "Erroneus nickname", [nickname])

  def format({:not_on_channel, channel}, client),
    do: numeric(442, client, "You're not on that channel", [channel])

  def format({:nickname_in_use, nickname}, client),
    do: numeric(433, client, "Nickname is already in use", [nickname])

  def format(:not_registered, client),
    do: numeric(451, client, "You have not registered")

  def format({:need_more_params, command}, client),
    do: numeric(461, client, "Not enough parameters", [command])

  def format(:already_registered, client),
    do: numeric(462, client, "You may not reregister")

  def format(:invalid_username, client),
    do: numeric(468, client, "Invalid username", ["USER"])

  def format({:channel_is_full, channel}, client),
    do: numeric(471, client, "Cannot join channel (+l)", [channel])

  def format({:unknown_mode, mode}, client),
    do: numeric(472, client, "is unknown mode char to me", [<<mode::utf8>>])

  def format({:banned_from_chan, channel}, client),
    do: numeric(474, client, "Cannot join channel (+b)", [channel])

  def format({:bad_channel_key, channel}, client),
    do: numeric(475, client, "Cannot join channel (+k)", [channel])

  def format({:bad_chan_mask, channel}, client),
    do: numeric(476, client, "Bad Channel Mask", [channel])

  def format({:chan_o_privs_needed, channel}, client),
    do: numeric(482, client, "You're not channel operator", [channel])

  def format(:users_dont_match, client),
    do: numeric(502, client, "Cant change mode for other users")

  def format(_other, _client), do: nil

  defp numeric(number, client, message, params \\ [])

  defp numeric(number, client, nil, params) do
    %Message{
      source: @server_name,
      command: number |> to_string() |> String.pad_leading(3, "0"),
      params: [client.nickname || "*" | params]
    }
  end

  defp numeric(number, client, message, params) do
    %Message{
      source: @server_name,
      command: number |> to_string() |> String.pad_leading(3, "0"),
      params: [client.nickname || "*" | params] ++ [message]
    }
  end
end
