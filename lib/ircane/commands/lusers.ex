defmodule IRCane.Commands.Lusers do
  alias IRCane.ChannelRegistry
  alias IRCane.ClientSupervisor
  alias IRCane.NickRegistry

  def handle(_params, state) do
    %{active: connections} =
      DynamicSupervisor.count_children(ClientSupervisor)

    users = Registry.count(NickRegistry)
    channels = Registry.count(ChannelRegistry)

    reply = %{
      users: users,
      invisible: 0,
      servers: 1,
      operators: 0,
      unknown: connections - users,
      channels: channels,
      max_users: users
    }

    {:ok, {:lusers, reply}, state}
  end
end
