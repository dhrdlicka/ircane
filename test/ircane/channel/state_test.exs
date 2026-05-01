defmodule IRCane.Channel.StateTest do
  use ExUnit.Case

  alias IRCane.Channel.Modes
  alias IRCane.Channel.State, as: ChannelState
  alias IRCane.Channel.Topic

  import Mimic
  import IRCane.TestFactory

  @moduletag :capture_log

  setup do
    copy(Modes)

    client = build(:user_state)

    {:ok, channel} = ChannelState.new("#prejoined")
    {:ok, channel} = ChannelState.join(channel, client, make_ref())

    {:ok, client: client, channel: channel}
  end

  describe "new/1" do
    test "creates a new channel state with the given name" do
      assert {:ok, state} = ChannelState.new("#test")

      assert %{
               name: "#test",
               new: true,
               topic: nil,
               modes: %{},
               members: %{}
             } = state

      assert map_size(state.members) == 0
    end

    test "returns an error if channel name does not start with a valid prefix" do
      assert {:error, {:bad_chan_mask, "test"}} = ChannelState.new("test")
    end

    test "returns an error if channel name contains invalid characters" do
      assert {:error, {:bad_chan_mask, "#bad channel"}} = ChannelState.new("#bad channel")
      assert {:error, {:bad_chan_mask, "#bad,channel"}} = ChannelState.new("#bad,channel")
      assert {:error, {:bad_chan_mask, "#bad\achannel"}} = ChannelState.new("#bad\achannel")
    end
  end

  describe "join/4" do
    test "allows a client to join a channel", %{client: client} do
      {:ok, state} = ChannelState.new("#test")

      expect(Modes, :authorize, fn
        ^state, :join, ^client, _opts -> :ok
      end)

      assert {:ok, %ChannelState{}} = ChannelState.join(state, client, make_ref())
    end

    test "saves membership information", %{client: client} do
      {:ok, state} = ChannelState.new("#test")

      expect(Modes, :authorize, fn
        ^state, :join, ^client, _opts -> :ok
      end)

      monitor_ref = make_ref()

      {:ok, new_state} = ChannelState.join(state, client, monitor_ref)

      client_pid = client.pid
      assert %{members: %{^client_pid => membership}} = new_state

      assert %{
               nickname: "nick",
               username: "user",
               hostname: "host",
               monitor_ref: ^monitor_ref
             } = membership
    end

    test "does not allow a client to join twice", %{client: client} do
      {:ok, state} = ChannelState.new("#test")

      expect(Modes, :authorize, 1, fn
        ^state, :join, ^client, _opts -> :ok
      end)

      {:ok, state} = ChannelState.join(state, client, make_ref())

      assert :noop = ChannelState.join(state, client, make_ref())
    end

    test "makes the first member an operator", %{client: client} do
      {:ok, state} = ChannelState.new("#test")

      expect(Modes, :authorize, fn
        ^state, :join, ^client, _opts -> :ok
      end)

      {:ok, new_state} = ChannelState.join(state, client, make_ref())

      refute new_state.new
      assert map_size(new_state.members) == 1
      assert [:operator] = new_state.members[client.pid].roles
    end

    test "does not make subsequent new members operators", %{client: client} do
      {:ok, state} = ChannelState.new("#test")

      expect(Modes, :authorize, 2, fn
        _state, :join, _client, _opts -> :ok
      end)

      {:ok, new_state} = ChannelState.join(state, client, make_ref())

      other_client = build(:user_state, pid: build(:pid), nickname: "other")

      assert {:ok, final_state} = ChannelState.join(new_state, other_client, make_ref())
      assert [] = final_state.members[other_client.pid].roles
    end

    test "denies join if Modes.authorize/4 returns an error", %{client: client} do
      {:ok, state} = ChannelState.new("#test")

      expect(Modes, :authorize, fn
        ^state, :join, ^client, _opts -> {:error, :banned_from_chan}
      end)

      assert {:error, :banned_from_chan} = ChannelState.join(state, client, make_ref())
    end

    test "passes channel key to Modes.authorize/4", %{client: client} do
      {:ok, state} = ChannelState.new("#test")

      expect(Modes, :authorize, fn
        ^state, :join, ^client, opts ->
          assert opts[:key] == "secret"
          :ok
      end)

      {:ok, _new_state} = ChannelState.join(state, client, make_ref(), "secret")
    end

    test "passes nil key to Modes.authorize/4 when no key is provided", %{client: client} do
      {:ok, state} = ChannelState.new("#test")

      expect(Modes, :authorize, fn
        ^state, :join, ^client, opts ->
          refute opts[:key]
          :ok
      end)

      {:ok, _new_state} = ChannelState.join(state, client, make_ref())
    end
  end

  describe "part/2" do
    test "allows a client to part a channel", %{channel: channel, client: client} do
      assert {:ok, {new_state, member}} = ChannelState.part(channel, client)
      assert channel.members[client.pid] == member
      refute Map.has_key?(new_state.members, client.pid)
    end

    test "returns an error if the client is not on the channel", %{client: client} do
      {:ok, state} = ChannelState.new("#test")

      assert {:error, :not_on_channel} = ChannelState.part(state, client)
    end
  end

  describe "quit/2" do
    test "removes a client from the channel", %{channel: channel, client: client} do
      {new_state, member} = ChannelState.quit(channel, client.pid)
      assert channel.members[client.pid] == member
      refute Map.has_key?(new_state.members, client.pid)
    end

    test "returns unchanged state and nil member if the client was not on the channel", %{
      client: client
    } do
      {:ok, state} = ChannelState.new("#test")

      assert {^state, nil} = ChannelState.quit(state, client.pid)
    end
  end

  describe "empty?/1" do
    test "returns true when the channel has no members" do
      {:ok, state} = ChannelState.new("#test")

      assert ChannelState.empty?(state)
    end

    test "returns false when the channel has members", %{channel: channel} do
      refute ChannelState.empty?(channel)
    end
  end

  describe "member/2" do
    test "finds a member by nickname case-insensitively", %{channel: channel} do
      other_client = build(:user_state, pid: build(:pid), nickname: "other")
      assert {:ok, prejoined_with_other} = ChannelState.join(channel, other_client, make_ref())

      assert {:ok, {pid, membership}} = ChannelState.member(prejoined_with_other, "OtHeR")
      assert pid == other_client.pid
      assert membership.nickname == "other"
    end

    test "returns an error when the nickname is not present", %{channel: channel} do
      assert {:error, {:user_not_in_channel, "missing", "#prejoined"}} =
               ChannelState.member(channel, "missing")
    end
  end

  describe "member?/2" do
    test "checks membership by pid", %{channel: channel, client: client} do
      outsider = build(:user_state, pid: build(:pid), nickname: "outsider")

      assert ChannelState.member?(channel, client.pid)
      refute ChannelState.member?(channel, outsider.pid)
    end

    test "checks membership by nickname case-insensitively", %{channel: channel} do
      assert ChannelState.member?(channel, "NiCk")
      refute ChannelState.member?(channel, "missing")
    end
  end

  describe "update_member_nickname/2" do
    test "updates the stored nickname for a joined member", %{channel: channel, client: client} do
      renamed_client = %{client | nickname: "renamed"}

      updated_state = ChannelState.update_member_nickname(channel, renamed_client)

      assert updated_state.members[client.pid].nickname == "renamed"
    end

    test "returns the original state when the member is not present", %{channel: channel} do
      outsider = build(:user_state, pid: build(:pid), nickname: "outsider")

      assert channel == ChannelState.update_member_nickname(channel, outsider)
    end
  end

  describe "has_role?/3" do
    test "returns true when the member has the exact role", %{channel: channel, client: client} do
      assert ChannelState.has_role?(channel, client.pid, :operator)
    end

    test "uses role hierarchy when comparing roles", %{channel: channel, client: client} do
      assert ChannelState.has_role?(channel, client.pid, :voice)
      refute ChannelState.has_role?(channel, client.pid, :founder)
    end

    test "returns false for non-members", %{channel: channel} do
      outsider = build(:user_state, pid: build(:pid), nickname: "outsider")

      refute ChannelState.has_role?(channel, outsider.pid, :voice)
    end
  end

  describe "metadata/1" do
    test "returns channel metadata", %{channel: channel} do
      other_client = build(:user_state, pid: build(:pid), nickname: "other")
      assert {:ok, prejoined_with_other} = ChannelState.join(channel, other_client, make_ref())
      topic = build(:topic)

      state = %{
        prejoined_with_other
        | topic: topic,
          modes: Map.put(prejoined_with_other.modes, :secret?, true)
      }

      assert %{
               name: "#prejoined",
               topic: ^topic,
               secret?: true,
               member_count: 2
             } = ChannelState.metadata(state)
    end
  end

  describe "names/2" do
    test "returns all members for a public channel even to outsiders", %{channel: channel} do
      other_client = build(:user_state, pid: build(:pid), nickname: "other")
      outsider = build(:user_state, pid: build(:pid), nickname: "outsider")
      assert {:ok, prejoined_with_other} = ChannelState.join(channel, other_client, make_ref())

      assert {:public, members} = ChannelState.names(prejoined_with_other, outsider.pid)
      assert Enum.sort(Enum.map(members, & &1.nickname)) == ["nick", "other"]
    end

    test "returns all members for a secret channel to joined members", %{
      channel: channel,
      client: client
    } do
      other_client = build(:user_state, pid: build(:pid), nickname: "other")
      assert {:ok, prejoined_with_other} = ChannelState.join(channel, other_client, make_ref())

      secret_state = %{
        prejoined_with_other
        | modes: Map.put(prejoined_with_other.modes, :secret?, true)
      }

      assert {:secret, members} = ChannelState.names(secret_state, client.pid)
      assert Enum.sort(Enum.map(members, & &1.nickname)) == ["nick", "other"]
    end

    test "hides secret channels from outsiders", %{channel: channel} do
      outsider = build(:user_state, pid: build(:pid), nickname: "outsider")
      secret_state = %{channel | modes: Map.put(channel.modes, :secret?, true)}

      assert {:none, []} = ChannelState.names(secret_state, outsider.pid)
    end
  end

  describe "topic/2" do
    test "returns the topic for public channels", %{channel: channel} do
      outsider = build(:user_state, pid: build(:pid), nickname: "outsider")
      topic = build(:topic, topic: "hello")
      state = %{channel | topic: topic}

      assert {:ok, ^topic} = ChannelState.topic(state, outsider.pid)
    end

    test "returns the topic for members in a secret channel", %{channel: channel, client: client} do
      topic = build(:topic, topic: "secret")
      state = %{channel | topic: topic, modes: Map.put(channel.modes, :secret?, true)}

      assert {:ok, ^topic} = ChannelState.topic(state, client.pid)
    end

    test "returns no_such_channel for outsiders in a secret channel", %{channel: channel} do
      outsider = build(:user_state, pid: build(:pid), nickname: "outsider")
      secret_state = %{channel | modes: Map.put(channel.modes, :secret?, true)}

      assert {:error, {:no_such_channel, "#prejoined"}} =
               ChannelState.topic(secret_state, outsider.pid)
    end
  end

  describe "mode/2" do
    test "returns visible modes for public channels", %{channel: channel} do
      outsider = build(:user_state, pid: build(:pid), nickname: "outsider")

      assert {:ok, modes} = ChannelState.mode(channel, outsider.pid)
      assert Enum.sort(modes) == Enum.sort([:protected_topic, :no_external_messages])
    end

    test "returns modes to members in a secret channel", %{channel: channel, client: client} do
      state = %{
        channel
        | modes:
            channel.modes
            |> Map.put(:secret?, true)
            |> Map.put(:moderated?, true)
      }

      assert {:ok, modes} = ChannelState.mode(state, client.pid)

      assert Enum.sort(modes) ==
               Enum.sort([:secret, :moderated, :protected_topic, :no_external_messages])
    end

    test "returns no_such_channel for outsiders in a secret channel", %{channel: channel} do
      outsider = build(:user_state, pid: build(:pid), nickname: "outsider")
      secret_state = %{channel | modes: Map.put(channel.modes, :secret?, true)}

      assert {:error, {:no_such_channel, "#prejoined"}} =
               ChannelState.mode(secret_state, outsider.pid)
    end
  end

  describe "update_topic/3" do
    test "updates the topic for an authorized member", %{channel: channel, client: client} do
      assert {:ok, updated_state} = ChannelState.update_topic(channel, client, "new topic")

      assert %Topic{topic: "new topic", set_by: "nick", set_at: %DateTime{}} =
               updated_state.topic
    end

    test "returns an error for a non-operator when topic protection is enabled", %{
      channel: channel
    } do
      other_client = build(:user_state, pid: build(:pid), nickname: "other")
      assert {:ok, prejoined_with_other} = ChannelState.join(channel, other_client, make_ref())

      assert {:error, {:chan_o_privs_needed, "#prejoined"}} =
               ChannelState.update_topic(prejoined_with_other, other_client, "new topic")
    end

    test "returns an error for an outsider", %{channel: channel} do
      outsider = build(:user_state, pid: build(:pid), nickname: "outsider")

      assert {:error, {:not_on_channel, "#prejoined"}} =
               ChannelState.update_topic(channel, outsider, "new topic")
    end
  end

  describe "update_mode/3" do
    test "applies mode changes for an operator", %{channel: channel, client: client} do
      assert {:ok, {updated_state, applied_updates, []}} =
               ChannelState.update_mode(channel, client, [{:add, :secret}])

      assert updated_state.modes.secret?
      assert applied_updates == [{:add, :secret}]
    end

    test "collects authorization errors for unauthorized members", %{channel: channel} do
      other_client = build(:user_state, pid: build(:pid), nickname: "other")
      assert {:ok, prejoined_with_other} = ChannelState.join(channel, other_client, make_ref())

      assert {:ok, {same_state, [], [{:chan_o_privs_needed, "#prejoined"}]}} =
               ChannelState.update_mode(prejoined_with_other, other_client, [{:add, :secret}])

      refute same_state.modes.secret?
      assert same_state == prejoined_with_other
    end
  end

  describe "role_changes/2" do
    test "returns changed roles for existing members", %{channel: channel, client: client} do
      updated_members =
        Map.update!(channel.members, client.pid, fn membership ->
          %{membership | roles: [:operator, :voice]}
        end)

      new_state = %{channel | members: updated_members}

      assert ChannelState.role_changes(new_state, channel) == [
               {client.pid, [:operator, :voice]}
             ]
    end

    test "omits unchanged members", %{channel: channel} do
      other_client = build(:user_state, pid: build(:pid), nickname: "other")
      assert {:ok, prejoined_with_other} = ChannelState.join(channel, other_client, make_ref())

      assert ChannelState.role_changes(prejoined_with_other, prejoined_with_other) == []
    end

    test "treats newly added members with roles as changes", %{channel: channel} do
      new_member_pid = build(:pid)

      membership =
        build(:membership,
          nickname: "newbie",
          username: "newbie_user",
          hostname: "newbie_host",
          roles: [:voice]
        )

      new_state = %{channel | members: Map.put(channel.members, new_member_pid, membership)}

      assert ChannelState.role_changes(new_state, channel) == [{new_member_pid, [:voice]}]
    end
  end
end
