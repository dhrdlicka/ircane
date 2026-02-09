defmodule IRCane.Channel.State do
  alias IRCane.Channel.Membership
  alias IRCane.Channel.Modes
  alias IRCane.Channel.Role
  alias IRCane.Channel.Topic
  alias IRCane.Client
  alias IRCane.Protocol.Mode

  defstruct name: nil,
            topic: nil,
            modes: %{
              bans: MapSet.new(),
              channel_limit: nil,
              key: nil,
              invite_only?: false,
              moderated?: false,
              secret?: false,
              protected_topic?: true,
              no_external_messages?: true
            },
            members: %{},
            new: true

  @type t ::
          %__MODULE__{
            name: String.t(),
            topic: Topic.t() | nil,
            modes: %{optional(atom()) => any()},
            members: %{optional(pid()) => Membership.t()},
            new: boolean()
          }

  @spec create(String.t()) :: {:ok, t()} | {:error, atom()}
  def create(name) do
    {:ok, %__MODULE__{name: name}}
  end

  @spec join(t(), Client.t(), String.t() | nil) :: {:ok, t()} | :noop | {:error, atom()}
  def join(channel_state, client, key \\ nil) do
    if not is_member?(channel_state, client.pid) do
      with :ok <- Modes.authorize(channel_state, :join, client, key: key) do
        roles = if channel_state.new, do: [:operator], else: []
        membership = %Membership{nickname: client.nickname, roles: roles}
        members = Map.put(channel_state.members, client.pid, membership)

        {:ok, %{channel_state | members: members, new: false}}
      end
    else
      :noop
    end
  end

  @spec names(t(), Client.t()) :: {:ok, [Membership.t()]} | {:error, atom()}
  def names(channel_state, _client) do
    {:ok, Map.values(channel_state.members)}
  end

  @spec part(t(), Client.t()) :: {:ok, t()} | {:error, atom()}
  def part(channel_state, client) do
    if is_member?(channel_state, client.pid) do
      members = Map.delete(channel_state.members, client.pid)
      {:ok, %{channel_state | members: members}}
    else
      {:error, :not_on_channel}
    end
  end

  @spec quit(t(), Client.t()) :: t()
  def quit(channel_state, client) do
    %{channel_state | members: Map.delete(channel_state.members, client.pid)}
  end

  @spec topic(t(), Client.t()) :: {:ok, Topic.t()} | {:error, atom()}
  def topic(channel_state, _client) do
    {:ok, channel_state.topic}
  end

  @spec update_topic(t(), Client.t(), String.t()) :: {:ok, t()} | {:error, atom()}
  def update_topic(channel_state, client, new_topic) do
    with :ok <- Modes.authorize(channel_state, :update_topic, client) do
      topic = %Topic{topic: new_topic, set_by: client.nickname, set_at: DateTime.utc_now()}
      {:ok, %{channel_state | topic: topic}}
    end
  end

  @spec update_member_nickname(t(), Client.t()) :: t()
  def update_member_nickname(channel_state, client) do
    membership = channel_state.members[client.pid]
    members = %{channel_state.members | client.pid => %{membership | nickname: client.nickname}}
    %{channel_state | members: members}
  end

  @spec mode(t(), Client.t()) :: {:ok, [Mode.t()]} | {:error, atom()}
  def mode(channel_state, _client) do
    modes = Modes.current(channel_state)
    {:ok, modes}
  end

  @spec update_mode(t(), Client.t(), list({:add | :remove, Mode.t()})) ::
          {:ok, {t(), list({:add | :remove, Mode.t()}), list(atom())}} | {:error, atom()}
  def update_mode(channel_state, client, mode_updates) do
    Modes.apply(channel_state, mode_updates, client)
  end

  @spec empty?(t()) :: boolean()
  def empty?(channel_state) do
    map_size(channel_state.members) == 0
  end

  @spec member(t(), String.t()) :: {:ok, {pid(), Membership.t()}} | {:error, atom()}
  def member(channel_state, nickname) do
    downcased = String.downcase(nickname)

    Enum.find_value(
      channel_state.members,
      {:error, {:user_not_in_channel, nickname, channel_state.name}},
      fn
        {_pid, %{nickname: member_nick}} = pair ->
          if String.downcase(member_nick) == downcased,
            do: {:ok, pair},
            else: false
      end
    )
  end

  @spec is_member?(t(), pid() | String.t()) :: boolean()
  def is_member?(channel_state, client_pid) when is_pid(client_pid) do
    Map.has_key?(channel_state.members, client_pid)
  end

  def is_member?(channel_state, nickname) when is_binary(nickname) do
    downcased = String.downcase(nickname)

    Enum.any?(channel_state.members, fn
      {_pid, %{nickname: member_nick}} ->
        String.downcase(member_nick) == downcased
    end)
  end

  @spec has_role?(t(), pid(), Role.t()) :: boolean()
  def has_role?(channel_state, client_pid, role) do
    case channel_state.members do
      %{^client_pid => %{roles: roles}} ->
        roles
        |> Role.max()
        |> Role.compare(role) >= 0

      _ ->
        false
    end
  end
end
