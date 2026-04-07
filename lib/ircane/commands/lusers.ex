defmodule IRCane.Commands.Lusers do
  @moduledoc false
  alias IRCane.Stats

  def handle(_params, state) do
    stats = Stats.snapshot()

    reply = %{
      users: stats.current_users,
      invisible: 0,
      servers: 1,
      operators: 0,
      unknown: stats.current_connections - stats.current_users,
      channels: stats.current_channels,
      max_users: stats.peak_users
    }

    {:ok, {:lusers, reply}, state}
  end
end
