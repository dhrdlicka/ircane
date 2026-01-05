defmodule IRCane do
  @moduledoc """
  Documentation for `IRCane`.
  """

  use Application

  require Logger

  def start(_type, _args) do
    Logger.notice("Starting IRCane IRC server")

    children = [
      {DynamicSupervisor, name: IRCane.ClientSupervisor},
      {DynamicSupervisor, name: IRCane.ChannelSupervisor},
      {Registry, keys: :unique, name: IRCane.ChannelRegistry},
      {Registry, keys: :unique, name: IRCane.NickRegistry},
      IRCane.ListenerSupervisor
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: IRCane.Supervisor) do
      {:ok, _pid} = result ->
        Logger.notice("IRCane IRC server started successfully")
        result

      {:error, reason} = error ->
        Logger.critical("Failed to start IRCane IRC server: #{inspect(reason)}")
        error
    end
  end
end
