alias IRCane.Channel
alias IRCane.ChannelRegistry
alias IRCane.Client
alias IRCane.Replies
alias IRCane.UserRegistry

defmodule IRCane.IEx.Helpers do
  def channel_state(name) do
    :sys.get_state({:via, Registry, {ChannelRegistry, name}})
  end

  def client_state(nickname) do
    :sys.get_state({:via, Registry, {UserRegistry, nickname}})
  end

  def transport_state(nickname) do
    {_, pid} = client_state(nickname).transport
    :sys.get_state(pid)
  end

  def state("#" <> _ = channel_name) do
    channel_state(channel_name)
  end

  def state(nickname) do
    client_state(nickname)
  end

  def stats_state() do
    :sys.get_state(IRCane.Stats)
  end
end

import IRCane.IEx.Helpers
