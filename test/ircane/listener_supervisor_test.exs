defmodule IRCane.ListenerSupervisorTest do
  use ExUnit.Case, async: true

  alias IRCane.ListenerSupervisor
  alias IRCane.Transport.TCP

  describe "listeners/0" do
    test "returns configured listeners" do
      assert ListenerSupervisor.listeners() == []
    end
  end

  describe "child_specs/1" do
    test "returns an empty list when no listeners are configured" do
      assert ListenerSupervisor.child_specs([]) == []
    end

    test "passes through explicit child specs" do
      assert [{ThousandIsland, options}] =
               ListenerSupervisor.child_specs([
                 {ThousandIsland,
                  [
                    handler_module: TCP,
                    port: 0,
                    read_timeout: 5_000
                  ]}
               ])

      assert options[:handler_module] == TCP
      assert options[:port] == 0
      assert options[:read_timeout] == 5_000
    end

    test "starts a listener from explicit runtime options" do
      [{ThousandIsland, options}] =
        ListenerSupervisor.child_specs([
          {ThousandIsland,
           [
             handler_module: TCP,
             port: 0,
             read_timeout: 5_000
           ]}
        ])

      server = start_supervised!({ThousandIsland, options})

      assert {:ok, {_address, port}} = ThousandIsland.listener_info(server)
      assert is_integer(port)
      assert port > 0
    end
  end
end
