defmodule IRCane.Channel.StateTest do
  use ExUnit.Case

  alias IRCane.Channel.Modes
  alias IRCane.Channel.State, as: ChannelState
  alias IRCane.Client

  import Mimic

  setup do
    client = %Client{
      pid: self(),
      nickname: "nick",
      username: "user",
      hostname: "host"
    }

    copy(Modes)

    {:ok, state} = ChannelState.create("#prejoined")

    stub(Modes, :authorize, fn
      ^state, :join, _client, _opts -> :ok
    end)

    {:ok, prejoined} = ChannelState.join(state, client, make_ref())

    {:ok, client: client, prejoined: prejoined}
  end

  describe "create/1" do
    test "creates a new channel state with the given name" do
      assert {:ok, state} = ChannelState.create("#test")

      assert %{
               name: "#test",
               new: true,
               topic: nil,
               modes: %{},
               members: %{}
             } = state

      assert map_size(state.members) == 0
    end
  end

  describe "join/4" do
    test "allows a client to join a channel", %{client: client} do
      {:ok, state} = ChannelState.create("#test")

      expect(Modes, :authorize, fn
        ^state, :join, ^client, _opts -> :ok
      end)

      assert {:ok, %ChannelState{}} = ChannelState.join(state, client, make_ref())
    end

    test "saves membership information", %{client: client} do
      {:ok, state} = ChannelState.create("#test")

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
      {:ok, state} = ChannelState.create("#test")

      expect(Modes, :authorize, 1, fn
        ^state, :join, ^client, _opts -> :ok
      end)

      {:ok, state} = ChannelState.join(state, client, make_ref())

      assert :noop = ChannelState.join(state, client, make_ref())
    end

    test "makes the first member an operator", %{client: client} do
      {:ok, state} = ChannelState.create("#test")

      expect(Modes, :authorize, fn
        ^state, :join, ^client, _opts -> :ok
      end)

      {:ok, new_state} = ChannelState.join(state, client, make_ref())

      refute new_state.new
      assert map_size(new_state.members) == 1
      assert [:operator] = new_state.members[client.pid].roles
    end

    test "does not make subsequent new members operators", %{client: client} do
      {:ok, state} = ChannelState.create("#test")

      expect(Modes, :authorize, 2, fn
        _state, :join, _client, _opts -> :ok
      end)

      {:ok, new_state} = ChannelState.join(state, client, make_ref())

      other_client = %Client{
        pid: spawn(fn -> :ok end),
        nickname: "other",
        username: "other_user",
        hostname: "other_host"
      }

      assert {:ok, final_state} = ChannelState.join(new_state, other_client, make_ref())
      assert [] = final_state.members[other_client.pid].roles
    end

    test "denies join if Modes.authorize/4 returns an error", %{client: client} do
      {:ok, state} = ChannelState.create("#test")

      expect(Modes, :authorize, fn
        ^state, :join, ^client, _opts -> {:error, :banned_from_chan}
      end)

      assert {:error, :banned_from_chan} = ChannelState.join(state, client, make_ref())
    end

    test "passes channel key to Modes.authorize/4", %{client: client} do
      {:ok, state} = ChannelState.create("#test")

      expect(Modes, :authorize, fn
        ^state, :join, ^client, opts ->
          assert opts[:key] == "secret"
          :ok
      end)

      {:ok, _new_state} = ChannelState.join(state, client, make_ref(), "secret")
    end

    test "passes nil key to Modes.authorize/4 when no key is provided", %{client: client} do
      {:ok, state} = ChannelState.create("#test")

      expect(Modes, :authorize, fn
        ^state, :join, ^client, opts ->
          refute opts[:key]
          :ok
      end)

      {:ok, _new_state} = ChannelState.join(state, client, make_ref())
    end
  end

  describe "part/2" do
    test "allows a client to part a channel", %{client: client, prejoined: prejoined} do
      assert {:ok, {new_state, member}} = ChannelState.part(prejoined, client)
      assert prejoined.members[client.pid] == member
      refute Map.has_key?(new_state.members, client.pid)
    end

    test "returns an error if the client is not on the channel", %{client: client} do
      {:ok, state} = ChannelState.create("#test")

      assert {:error, :not_on_channel} = ChannelState.part(state, client)
    end
  end

  describe "quit/2" do
    test "removes a client from the channel", %{client: client, prejoined: prejoined} do
      {new_state, member} = ChannelState.quit(prejoined, client.pid)
      assert prejoined.members[client.pid] == member
      refute Map.has_key?(new_state.members, client.pid)
    end

    test "returns unchanged state and nil member if the client was not on the channel", %{
      client: client
    } do
      {:ok, state} = ChannelState.create("#test")

      assert {^state, nil} = ChannelState.quit(state, client.pid)
    end
  end
end
