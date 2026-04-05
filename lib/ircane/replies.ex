defmodule IRCane.Replies do
  alias IRCane.Channel.Role
  alias IRCane.Protocol.Message
  alias IRCane.Protocol.Mode
  alias IRCane.Stats
  alias IRCane.Utils.ISupport

  @network_name "TestNet"
  @server_name "localhost"
  @version "ircane-0.1"
  @channel_modes Application.compile_env!(:ircane, :channel_modes)

  defp format_numeric(reply, client) do
    client = client || "*"

    case reply do
      :welcome ->
        %Message{
          source: @server_name,
          command: "001",
          params: [client, "Welcome to the #{@network_name} Network, #{client}"]
        }

      :your_host ->
        %Message{
          source: @server_name,
          command: "002",
          params: [client, "Your host is #{@server_name}, running version #{@version}"]
        }

      :created ->
        created_date = Stats.created_at()

        %Message{
          source: @server_name,
          command: "003",
          params: [client, "This server was created #{created_date}"]
        }

      :my_info ->
        %Message{
          source: @server_name,
          command: "004",
          params: [client, @server_name, @version, "ioOw", "blikmstnov", "blkov"]
        }

      :i_support ->
        ISupport.build()
        |> Enum.map(fn
          {key, value} -> "#{key |> Atom.to_string() |> String.upcase()}=#{value}"
          token -> token |> Atom.to_string() |> String.upcase()
        end)
        |> Enum.chunk_every(13)
        |> Enum.map(
          &%Message{
            source: @server_name,
            command: "005",
            params: [client | &1] ++ ["are supported by this server"]
          }
        )

      {:luser_client, users, invisibles, servers} ->
        %Message{
          source: @server_name,
          command: "251",
          params: [
            client,
            "There are #{users} users and #{invisibles} invisible on #{servers} servers"
          ]
        }

      {:luser_op, operators} ->
        %Message{
          source: @server_name,
          command: "252",
          params: [client, "#{operators}", "operator(s) online"]
        }

      {:luser_unknown, unknown} ->
        %Message{
          source: @server_name,
          command: "253",
          params: [client, "#{unknown}", "unknown connection(s)"]
        }

      {:luser_channels, channels} ->
        %Message{
          source: @server_name,
          command: "254",
          params: [client, "#{channels}", "channels formed"]
        }

      {:luser_me, clients, servers} ->
        %Message{
          source: @server_name,
          command: "255",
          params: [client, "I have #{clients} clients and #{servers} servers"]
        }

      {:local_users, users, max} ->
        %Message{
          source: @server_name,
          command: "265",
          params: [client, users, max, "Current local users: #{users}, max: #{max}"]
        }

      {:global_users, users, max} ->
        %Message{
          source: @server_name,
          command: "266",
          params: [client, users, max, "Current global users: #{users}, max: #{max}"]
        }

      {:channel_mode_is, target, modes} ->
        mode_strings =
          modes
          |> Enum.map(&{:add, &1})
          |> Mode.format(@channel_modes)

        %Message{source: @server_name, command: "324", params: [client, target | mode_strings]}

      {:names_reply, channel, names} ->
        %Message{source: @server_name, command: "353", params: [client, "=", channel, names]}

      {:end_of_names, channel} ->
        %Message{
          source: @server_name,
          command: "366",
          params: [client, channel, "End of /NAMES list"]
        }

      {:ban_list, target, mask} ->
        %Message{source: @server_name, command: "367", params: [client, target, mask]}

      {:end_of_ban_list, target} ->
        %Message{
          source: @server_name,
          command: "368",
          params: [client, target, "End of channel ban list"]
        }

      {:no_such_nick, nickname} ->
        %Message{
          source: @server_name,
          command: "401",
          params: [client, nickname, "No such nick/channel"]
        }

      {:no_such_channel, channel} ->
        %Message{
          source: @server_name,
          command: "403",
          params: [client, channel, "No such channel"]
        }

      {:no_topic, channel} ->
        %Message{
          source: @server_name,
          command: "331",
          params: [client, channel, "No topic is set"]
        }

      {:topic, channel, topic} ->
        %Message{source: @server_name, command: "332", params: [client, channel, topic]}

      {:topic_who_time, channel, nick, set_at} ->
        %Message{
          source: @server_name,
          command: "333",
          params: [client, channel, nick, "#{DateTime.to_unix(set_at)}"]
        }

      {:cannot_send_to_chan, channel} ->
        %Message{
          source: @server_name,
          command: "404",
          params: [client, channel, "Cannot send to channel"]
        }

      :input_too_long ->
        %Message{
          source: @server_name,
          command: "417",
          params: [client, "Input line was too long"]
        }

      {:unknown_command, command} ->
        %Message{
          source: @server_name,
          command: "421",
          params: [client, command, "Unknown command"]
        }

      :no_motd ->
        %Message{source: @server_name, command: "422", params: [client, "MOTD File is missing"]}

      {:erroneous_nickname, nickname} ->
        %Message{
          source: @server_name,
          command: "432",
          params: [client, nickname, "Erroneus nickname"]
        }

      {:not_on_channel, channel} ->
        %Message{
          source: @server_name,
          command: "442",
          params: [client, channel, "You're not on that channel"]
        }

      {:nickname_in_use, nickname} ->
        %Message{
          source: @server_name,
          command: "433",
          params: [client, nickname, "Nickname is already in use"]
        }

      :not_registered ->
        %Message{
          source: @server_name,
          command: "451",
          params: [client, "You have not registered"]
        }

      {:channel_is_full, channel} ->
        %Message{
          source: @server_name,
          command: "471",
          params: [client, channel, "Cannot join channel (+l)"]
        }

      {:unknown_mode, mode} ->
        %Message{
          source: @server_name,
          command: "472",
          params: [client, <<mode::utf8>>, "is unknown mode char to me"]
        }

      {:banned_from_chan, channel} ->
        %Message{
          source: @server_name,
          command: "474",
          params: [client, channel, "Cannot join channel (+b)"]
        }

      {:bad_channel_key, channel} ->
        %Message{
          source: @server_name,
          command: "475",
          params: [client, channel, "Cannot join channel (+k)"]
        }

      {:bad_chan_mask, channel} ->
        %Message{
          source: @server_name,
          command: "476",
          params: [client, channel, "Bad Channel Mask"]
        }

      {:chan_o_privs_needed, channel} ->
        %Message{
          source: @server_name,
          command: "482",
          params: [client, channel, "You're not channel operator"]
        }

      :users_dont_match ->
        %Message{
          source: @server_name,
          command: "502",
          params: [client, "Cant change mode for other users"]
        }

      {:need_more_params, command} ->
        %Message{
          source: @server_name,
          command: "461",
          params: [client, command, "Not enough parameters"]
        }

      other ->
        %Message{
          source: @server_name,
          command: "400",
          params: [client, "Unknown message: #{inspect(other)}"]
        }
    end
  end

  def format_error({:error, reason}, client) do
    format_numeric(reason, client)
  end

  def format_multiple(list, client) when is_list(list) do
    list
    |> Enum.map(fn
      {:error, _} = error -> format_error(error, client)
      {:ok, reply} -> format_message(reply, client)
    end)
    |> List.flatten()
  end

  def format_message(message, client \\ nil)

  def format_message(messages, client) when is_list(messages) do
    messages
    |> Enum.map(&format_message(&1, client))
    |> List.flatten()
  end

  def format_message({:pong, token}, _client) do
    [%Message{source: @server_name, command: "PONG", params: [@server_name, token]}]
  end

  def format_message({:join, client, channel}, _client) do
    [%Message{source: client.nickname, command: "JOIN", params: [channel]}]
  end

  def format_message({:part, client, channel, part_message}, _client) do
    [%Message{source: client.nickname, command: "PART", params: [channel, part_message]}]
  end

  def format_message({:privmsg, source, target, message}, _client) do
    [%Message{source: source.nickname, command: "PRIVMSG", params: [target, message]}]
  end

  def format_message({:notice, source, target, message}, _client) do
    [%Message{source: source.nickname, command: "NOTICE", params: [target, message]}]
  end

  def format_message(:rdns_in_progress, client) do
    [server_notice("*** Looking up your hostname...", client)]
  end

  def format_message({:rdns_successful, hostname}, client) do
    [server_notice("*** Found your hostname: #{hostname}", client)]
  end

  def format_message({:rdns_failed, hostname}, client) do
    [server_notice("*** Could not resolve your hostname; using your IP address (#{hostname}) instead", client)]
  end

  def format_message({:quit, source, quit_message}, _client) do
    [%Message{source: source.nickname, command: "QUIT", params: [quit_message]}]
  end

  def format_message({:nick, source, new_nick}, _client) do
    [%Message{source: source.nickname, command: "NICK", params: [new_nick]}]
  end

  def format_message({:topic, channel, %{topic: topic, nick: nick, set_at: set_at}}, client) do
    [
      {:topic, channel, topic},
      {:topic_who_time, channel, nick, set_at}
    ]
    |> Enum.map(&format_numeric(&1, client))
  end

  def format_message({:topic, source, channel, topic}, _client) do
    [%Message{source: source.nickname, command: "TOPIC", params: [channel, topic]}]
  end

  def format_message({:names, channel, members}, client) do
    member_list =
      members
      |> Enum.map_join(" ", fn
        %{nickname: nickname, roles: roles} ->
          prefix = roles |> Role.max() |> Role.prefix()
          prefix <> nickname
      end)

    [
      {:names_reply, channel, member_list},
      {:end_of_names, channel}
    ]
    |> Enum.map(&format_numeric(&1, client))
  end

  def format_message({:lusers, lusers}, client) do
    [
      {:luser_client, lusers.users, lusers.invisible, lusers.servers},
      {:luser_op, lusers.operators},
      {:luser_unknown, lusers.unknown},
      {:luser_channels, lusers.channels},
      {:luser_me, lusers.users, lusers.servers},
      {:local_users, lusers.users, lusers.max_users},
      {:global_users, lusers.users, lusers.max_users}
    ]
    |> Enum.map(&format_numeric(&1, client))
  end

  def format_message({:channel_mode, source, target, modes}, _client) do
    mode_strings = Mode.format(modes, @channel_modes)

    [%Message{source: source.nickname, command: "MODE", params: [target | mode_strings]}]
  end

  def format_message({:ban_list, target, bans}, client) do
    bans
    |> Enum.map(&{:ban_list, target, &1})
    |> Kernel.++([{:end_of_ban_list, target}])
    |> Enum.map(&format_numeric(&1, client))
  end

  def format_message({:kick, :server, channel, target, reason}, _client) do
    [%Message{source: @server_name, command: "KICK", params: [channel, target, reason]}]
  end

  def format_message({:kick, source, channel, target, reason}, _client) do
    [%Message{source: source.nickname, command: "KICK", params: [channel, target, reason]}]
  end

  def format_message({:error, reason}, _client) do
    [%Message{command: "ERROR", params: [reason]}]
  end

  def format_message(other, client) do
    [format_numeric(other, client)]
  end

  defp server_notice(message, client) do
    target = client || "*"

    %Message{
      source: @server_name,
      command: "NOTICE",
      params: [target, message]
    }
  end
end
