defmodule IRCane.Channel.State do
  alias IRCane.BanMask
  alias IRCane.Channel.Membership
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
      with :ok <- authorize(channel_state, :join, client, key: key) do
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
    with :ok <- authorize(channel_state, :update_topic, client) do
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
    modes =
      Enum.reject(
        [
          if(channel_state.modes.invite_only?, do: :invite_only),
          if(channel_state.modes.moderated?, do: :moderated),
          if(channel_state.modes.secret?, do: :secret),
          if(channel_state.modes.protected_topic?, do: :protected_topic),
          if(channel_state.modes.no_external_messages?, do: :no_external_messages),
          if(channel_state.modes.channel_limit,
            do: {:channel_limit, channel_state.modes.channel_limit}
          ),
          if(channel_state.modes.key, do: {:key, channel_state.modes.key})
        ],
        &is_nil/1
      )

    {:ok, modes}
  end

  @spec update_mode(t(), Client.t(), list({:add | :remove, Mode.t()})) ::
          {:ok, {t(), list({:add | :remove, Mode.t()}), list(atom())}} | {:error, atom()}
  def update_mode(channel_state, client, mode_updates) do
    result =
      Enum.reduce(mode_updates, {channel_state, [], []}, fn
        update, {channel_state, applied_updates, errors} ->
          with :ok <- authorize(channel_state, :update_mode, client, update: update) do
            case apply_mode(channel_state, update) do
              {:ok, new_channel_state, applied_update} ->
                {new_channel_state, [applied_update | applied_updates], errors}

              {:ok, new_channel_state} ->
                {new_channel_state, [update | applied_updates], errors}

              {:error, error} ->
                {channel_state, applied_updates, [error | errors]}

              _ ->
                {channel_state, applied_updates, errors}
            end
          else
            {:error, error} ->
              {channel_state, applied_updates, [error | errors]}
          end
      end)

    {:ok, result}
  end

  defp apply_mode(channel_state, {_op, :invite_only} = update),
    do: apply_boolean_mode(channel_state, :invite_only?, update)

  defp apply_mode(channel_state, {_op, :moderated} = update),
    do: apply_boolean_mode(channel_state, :moderated?, update)

  defp apply_mode(channel_state, {_op, :secret} = update),
    do: apply_boolean_mode(channel_state, :secret?, update)

  defp apply_mode(channel_state, {_op, :protected_topic} = update),
    do: apply_boolean_mode(channel_state, :protected_topic?, update)

  defp apply_mode(channel_state, {_op, :no_external_messages} = update),
    do: apply_boolean_mode(channel_state, :no_external_messages?, update)

  defp apply_mode(channel_state, {_op, {:operator, _nickname}} = update),
    do: apply_prefix_mode(channel_state, update)

  defp apply_mode(channel_state, {_op, {:voice, _nickname}} = update),
    do: apply_prefix_mode(channel_state, update)

  defp apply_mode(
         %{modes: %{channel_limit: old_limit}} = channel_state,
         {:add, {:channel_limit, new_limit}}
       )
       when old_limit != new_limit do
    {:ok, %{channel_state | modes: Map.put(channel_state.modes, :channel_limit, new_limit)}}
  end

  defp apply_mode(%{modes: %{channel_limit: limit}} = channel_state, {:remove, :channel_limit})
       when not is_nil(limit) do
    {:ok, %{channel_state | modes: Map.put(channel_state.modes, :channel_limit, nil)}}
  end

  defp apply_mode(%{modes: %{key: nil}} = channel_state, {:add, {:key, new_key}}) do
    {:ok, %{channel_state | modes: Map.put(channel_state.modes, :key, new_key)}}
  end

  defp apply_mode(%{modes: %{key: correct_key}} = channel_state, {:remove, {:key, key}})
       when key == correct_key do
    {:ok, %{channel_state | modes: Map.put(channel_state.modes, :key, nil)}}
  end

  defp apply_mode(%{modes: %{bans: bans}} = channel_state, {:add, {:ban, ban_mask}}) do
    if not MapSet.member?(bans, ban_mask) do
      new_bans = MapSet.put(bans, ban_mask)
      {:ok, %{channel_state | modes: Map.put(channel_state.modes, :bans, new_bans)}}
    else
      :noop
    end
  end

  defp apply_mode(%{modes: %{bans: bans}} = channel_state, {:remove, {:ban, ban_mask}}) do
    if MapSet.member?(bans, ban_mask) do
      new_bans = MapSet.delete(bans, ban_mask)
      {:ok, %{channel_state | modes: Map.put(channel_state.modes, :bans, new_bans)}}
    else
      :noop
    end
  end

  defp apply_mode(_channel_state, _update), do: :noop

  defp apply_boolean_mode(%{modes: modes} = channel_state, field_name, {op, _mode_name}) do
    case {op, Map.get(modes, field_name)} do
      {:add, false} -> {:ok, %{channel_state | modes: Map.put(modes, field_name, true)}}
      {:remove, true} -> {:ok, %{channel_state | modes: Map.put(modes, field_name, false)}}
      _ -> :noop
    end
  end

  defp apply_prefix_mode(channel_state, {op, {mode_name, nickname}}) do
    with {:ok, {pid, membership}} <- fetch_member(channel_state, nickname) do
      has_role = mode_name in membership.roles

      case {op, has_role} do
        {:add, false} ->
          membership = %{membership | roles: [mode_name | membership.roles]}
          members = %{channel_state.members | pid => membership}
          update = {op, {mode_name, membership.nickname}}
          {:ok, %{channel_state | members: members}, update}

        {:remove, true} ->
          membership = %{membership | roles: List.delete(membership.roles, mode_name)}
          members = %{channel_state.members | pid => membership}
          update = {op, {mode_name, membership.nickname}}
          {:ok, %{channel_state | members: members}, update}

        _ ->
          :noop
      end
    end
  end

  @spec authorize(t(), atom(), Client.t(), keyword()) :: :ok | {:error, atom()}
  def authorize(channel_state, action, client, opts \\ [])

  def authorize(channel_state, :join, client, opts) do
    key = Keyword.get(opts, :key)

    with :ok <- enforce_ban(channel_state, client),
         :ok <- enforce_channel_limit(channel_state),
         :ok <- enforce_key(channel_state, key),
         :ok <- enforce_invite_only(channel_state, client.pid) do
      :ok
    end
  end

  def authorize(channel_state, :speak, client, _opts) do
    with :ok <- enforce_no_external_messages(channel_state, client.pid),
         :ok <- enforce_moderated(channel_state, client.pid) do
      if is_banned?(channel_state, client),
        do: {:error, {:cannot_send_to_chan, channel_state.name}},
        else: :ok
    end
  end

  def authorize(channel_state, :update_topic, client, _opts) do
    with :ok <- ensure_member(channel_state, client.pid),
         :ok <- enforce_protected_topic(channel_state, client.pid) do
      :ok
    end
  end

  def authorize(channel_state, :update_mode, client, _opts) do
    with :ok <- ensure_member(channel_state, client.pid),
         :ok <- ensure_operator(channel_state, client.pid) do
      :ok
    end
  end

  def authorize(channel_state, :kick, client, _opts) do
    with :ok <- ensure_member(channel_state, client.pid),
         :ok <- ensure_operator(channel_state, client.pid) do
      :ok
    end
  end

  @spec empty?(t()) :: boolean()
  def empty?(channel_state) do
    map_size(channel_state.members) == 0
  end

  defp fetch_member(channel_state, nickname) do
    downcased = String.downcase(nickname)

    Enum.find_value(channel_state.members, {:error, {:no_such_nick, nickname}}, fn
      {_pid, %{nickname: member_nick}} = pair ->
        if String.downcase(member_nick) == downcased,
          do: {:ok, pair},
          else: false
    end)
  end

  defp is_operator?(channel_state, client_pid) do
    case channel_state.members do
      %{^client_pid => %{roles: roles}} ->
        roles
        |> Role.max()
        |> Role.compare(:operator) >= 0

      _ ->
        false
    end
  end

  defp is_voiced?(channel_state, client_pid) do
    case channel_state.members do
      %{^client_pid => %{roles: roles}} ->
        roles
        |> Role.max()
        |> Role.compare(:voice) >= 0

      _ ->
        false
    end
  end

  defp is_member?(channel_state, client_pid) do
    Map.has_key?(channel_state.members, client_pid)
  end

  def is_banned?(%{modes: %{bans: bans}}, client) do
    Enum.any?(bans, &BanMask.match?(&1, client))
  end

  defp ensure_member(channel_state, client_pid) do
    if is_member?(channel_state, client_pid),
      do: :ok,
      else: {:error, {:not_on_channel, channel_state.name}}
  end

  defp ensure_operator(channel_state, client_pid) do
    if is_operator?(channel_state, client_pid),
      do: :ok,
      else: {:error, {:chan_o_privs_needed, channel_state.name}}
  end

  defp enforce_ban(channel_state, client) do
    if is_banned?(channel_state, client),
      do: {:error, {:banned_from_chan, channel_state.name}},
      else: :ok
  end

  defp enforce_channel_limit(%{modes: %{channel_limit: nil}}), do: :ok

  defp enforce_channel_limit(channel_state) do
    if map_size(channel_state.members) < channel_state.modes.channel_limit,
      do: :ok,
      else: {:error, {:channel_is_full, channel_state.name}}
  end

  defp enforce_key(%{modes: %{key: nil}}, _key), do: :ok

  defp enforce_key(channel_state, key) do
    if channel_state.modes.key == key,
      do: :ok,
      else: {:error, {:bad_channel_key, channel_state.name}}
  end

  defp enforce_invite_only(_channel_state, _client_pid), do: :ok

  defp enforce_moderated(%{modes: %{moderated?: false}}, _client_pid), do: :ok

  defp enforce_moderated(channel_state, client_pid) do
    if is_operator?(channel_state, client_pid) or is_voiced?(channel_state, client_pid),
      do: :ok,
      else: {:error, {:cannot_send_to_chan, channel_state.name}}
  end

  defp enforce_protected_topic(%{modes: %{protected_topic?: false}}, _client_pid), do: :ok

  defp enforce_protected_topic(channel_state, client_pid),
    do: ensure_operator(channel_state, client_pid)

  defp enforce_no_external_messages(%{modes: %{no_external_messages?: false}}, _client_pid),
    do: :ok

  defp enforce_no_external_messages(channel_state, client_pid),
    do: ensure_member(channel_state, client_pid)
end
