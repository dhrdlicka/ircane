defmodule IRCane.User.State do
  @moduledoc false
  alias IRCane.User.ChannelMembership

  @enforce_keys [:pid]
  defstruct pid: nil,
            nickname: nil,
            username: nil,
            hostname: nil,
            realname: nil,
            registered?: false,
            modes: %{},
            away_message: nil,
            quit_message: nil,
            channels: %{}

  @type t :: %__MODULE__{
          pid: pid(),
          nickname: String.t() | nil,
          username: String.t() | nil,
          hostname: String.t() | nil,
          realname: String.t() | nil,
          registered?: boolean(),
          modes: %{optional(atom()) => any()},
          away_message: String.t() | nil,
          quit_message: String.t() | nil,
          channels: %{optional(pid()) => ChannelMembership.t()}
        }

  def new(pid) do
    %__MODULE__{pid: pid}
  end

  def update_nickname(state, nickname) do
    with false <- String.contains?(nickname, [" ", ",", "*", "?", "!", "@", "."]),
         false <- String.starts_with?(nickname, [":", "#", "+"]),
         true <- String.printable?(nickname) do
      {:ok, %{state | nickname: nickname}}
    else
      _ ->
        {:error, :erroneous_nickname}
    end
  end

  def update_username(state, username) do
    with false <- String.contains?(username, [" ", ",", "*", "?", "!", "@"]),
         false <- String.starts_with?(username, [":"]),
         true <- String.printable?(username) do
      {:ok, %{state | username: username}}
    else
      _ ->
        {:error, :invalid_username}
    end
  end

  def update_realname(state, realname) do
    %{state | realname: realname}
  end

  def update_hostname(state, hostname) do
    %{state | hostname: hostname}
  end

  def try_register(%{nickname: nil}), do: :noop

  def try_register(%{username: nil}), do: :noop

  def try_register(%{registered?: false} = state) do
    {:ok, %{state | registered?: true}}
  end

  def try_register(_state), do: :noop

  def add_channel(state, channel_pid, channel_name, monitor_ref) do
    joined_channel = %ChannelMembership{
      name: channel_name,
      monitor_ref: monitor_ref
    }

    %{state | channels: Map.put(state.channels, channel_pid, joined_channel)}
  end

  def pop_channel(state, channel_pid) do
    {channel, other_channels} = Map.pop(state.channels, channel_pid)
    {channel, %{state | channels: other_channels}}
  end

  def update_channel_roles(state, channel_pid, new_roles) do
    update_in(state.channels[channel_pid].roles, fn _ -> new_roles end)
  end

  def quit(state, message) do
    %{state | quit_message: message}
  end

  def metadata(state) do
    %{
      nickname: state.nickname,
      username: state.username,
      hostname: state.hostname,
      away?: not is_nil(state.away_message),
      invisible?: Map.get(state.modes, :invisible, false)
    }
  end
end
