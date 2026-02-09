defmodule IRCane.Channel.Modes do
  alias IRCane.BanMask
  alias IRCane.Channel.State, as: ChannelState
  alias IRCane.Client
  alias IRCane.Protocol.Mode

  @spec authorize(ChannelState.t(), atom(), Client.t(), keyword()) :: :ok | {:error, atom()}
  def authorize(channel_state, action, client, opts \\ [])

  def authorize(channel_state, :join, client, opts) do
    key = Keyword.get(opts, :key)

    with :ok <- enforce_ban_on_join(channel_state, client),
         :ok <- enforce_channel_limit(channel_state),
         :ok <- enforce_key(channel_state, key),
         :ok <- enforce_invite_only_on_join(channel_state, client.pid) do
      :ok
    end
  end

  def authorize(channel_state, :speak, client, _opts) do
    with :ok <- enforce_no_external_messages(channel_state, client.pid),
         :ok <- enforce_moderated(channel_state, client.pid),
         :ok <- enforce_ban_on_speak(channel_state, client) do
      :ok
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

  def authorize(channel_state, :invite, client, _opts) do
    with :ok <- ensure_member(channel_state, client.pid),
         :ok <- enforce_invite_only_on_invite(channel_state, client.pid) do
      :ok
    end
  end

  defp ensure_member(channel_state, client_pid) do
    if ChannelState.is_member?(channel_state, client_pid),
      do: :ok,
      else: {:error, {:not_on_channel, channel_state.name}}
  end

  defp ensure_operator(channel_state, client_pid) do
    if ChannelState.has_role?(channel_state, client_pid, :operator),
      do: :ok,
      else: {:error, {:chan_o_privs_needed, channel_state.name}}
  end

  defp is_banned?(%{modes: %{bans: bans}}, client) do
    Enum.any?(bans, &BanMask.match?(&1, client))
  end

  defp enforce_ban_on_join(channel_state, client) do
    if is_banned?(channel_state, client),
      do: {:error, {:banned_from_chan, channel_state.name}},
      else: :ok
  end

  defp enforce_ban_on_speak(channel_state, client) do
    if is_banned?(channel_state, client),
      do: {:error, {:cannot_send_to_chan, channel_state.name}},
      else: :ok
  end

  defp enforce_channel_limit(%{modes: %{channel_limit: nil}}),
    do: :ok

  defp enforce_channel_limit(channel_state) do
    if map_size(channel_state.members) < channel_state.modes.channel_limit,
      do: :ok,
      else: {:error, {:channel_is_full, channel_state.name}}
  end

  defp enforce_key(%{modes: %{key: nil}}, _key),
    do: :ok

  defp enforce_key(channel_state, key) do
    if channel_state.modes.key == key,
      do: :ok,
      else: {:error, {:bad_channel_key, channel_state.name}}
  end

  defp enforce_invite_only_on_join(_channel_state, _client_pid),
    do: :ok

  defp enforce_invite_only_on_invite(%{modes: %{invite_only?: false}}, _client_pid),
    do: :ok

  defp enforce_invite_only_on_invite(channel_state, client_pid),
    do: ensure_operator(channel_state, client_pid)

  defp enforce_moderated(%{modes: %{moderated?: false}}, _client_pid),
    do: :ok

  defp enforce_moderated(channel_state, client_pid) do
    if ChannelState.has_role?(channel_state, client_pid, :voice),
      do: :ok,
      else: {:error, {:cannot_send_to_chan, channel_state.name}}
  end

  defp enforce_protected_topic(%{modes: %{protected_topic?: false}}, _client_pid),
    do: :ok

  defp enforce_protected_topic(channel_state, client_pid),
    do: ensure_operator(channel_state, client_pid)

  defp enforce_no_external_messages(%{modes: %{no_external_messages?: false}}, _client_pid),
    do: :ok

  defp enforce_no_external_messages(channel_state, client_pid),
    do: ensure_member(channel_state, client_pid)

  @spec apply(ChannelState.t(), [Mode.mode_change()], Client.t()) ::
          {:ok, {ChannelState.t(), [Mode.mode_change()], [atom()]}} | {:error, atom()}
  def apply(channel_state, updates, client) do
    result =
      Enum.reduce(updates, {channel_state, [], []}, fn
        update, {channel_state, applied_updates, errors} ->
          with :ok <- authorize(channel_state, :update_mode, client, update: update) do
            case do_apply(channel_state, update, client) do
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

  defp do_apply(channel_state, {_op, :invite_only} = update, _client),
    do: apply_boolean_mode(channel_state, :invite_only?, update)

  defp do_apply(channel_state, {_op, :moderated} = update, _client),
    do: apply_boolean_mode(channel_state, :moderated?, update)

  defp do_apply(channel_state, {_op, :secret} = update, _client),
    do: apply_boolean_mode(channel_state, :secret?, update)

  defp do_apply(channel_state, {_op, :protected_topic} = update, _client),
    do: apply_boolean_mode(channel_state, :protected_topic?, update)

  defp do_apply(channel_state, {_op, :no_external_messages} = update, _client),
    do: apply_boolean_mode(channel_state, :no_external_messages?, update)

  defp do_apply(channel_state, {_op, {:operator, _nickname}} = update, client),
    do: apply_prefix_mode(channel_state, update, client)

  defp do_apply(channel_state, {_op, {:voice, _nickname}} = update, client),
    do: apply_prefix_mode(channel_state, update, client)

  defp do_apply(
         %{modes: %{channel_limit: old_limit}} = channel_state,
         {:add, {:channel_limit, new_limit}},
         _client
       )
       when old_limit != new_limit do
    {:ok, %{channel_state | modes: Map.put(channel_state.modes, :channel_limit, new_limit)}}
  end

  defp do_apply(
         %{modes: %{channel_limit: limit}} = channel_state,
         {:remove, :channel_limit},
         _client
       )
       when not is_nil(limit) do
    {:ok, %{channel_state | modes: Map.put(channel_state.modes, :channel_limit, nil)}}
  end

  defp do_apply(%{modes: %{key: nil}} = channel_state, {:add, {:key, new_key}}, _client) do
    {:ok, %{channel_state | modes: Map.put(channel_state.modes, :key, new_key)}}
  end

  defp do_apply(%{modes: %{key: correct_key}} = channel_state, {:remove, {:key, key}}, _client)
       when key == correct_key do
    {:ok, %{channel_state | modes: Map.put(channel_state.modes, :key, nil)}}
  end

  defp do_apply(%{modes: %{bans: bans}} = channel_state, {:add, {:ban, ban_mask}}, _client) do
    if not MapSet.member?(bans, ban_mask) do
      new_bans = MapSet.put(bans, ban_mask)
      {:ok, %{channel_state | modes: Map.put(channel_state.modes, :bans, new_bans)}}
    else
      :noop
    end
  end

  defp do_apply(%{modes: %{bans: bans}} = channel_state, {:remove, {:ban, ban_mask}}, _client) do
    if MapSet.member?(bans, ban_mask) do
      new_bans = MapSet.delete(bans, ban_mask)
      {:ok, %{channel_state | modes: Map.put(channel_state.modes, :bans, new_bans)}}
    else
      :noop
    end
  end

  defp do_apply(_channel_state, _update, _client), do: :noop

  defp apply_boolean_mode(%{modes: modes} = channel_state, field_name, {op, _mode_name}) do
    case {op, Map.get(modes, field_name)} do
      {:add, false} -> {:ok, %{channel_state | modes: Map.put(modes, field_name, true)}}
      {:remove, true} -> {:ok, %{channel_state | modes: Map.put(modes, field_name, false)}}
      _ -> :noop
    end
  end

  defp apply_prefix_mode(channel_state, {op, {mode_name, nickname}}, _client) do
    with {:ok, {pid, membership}} <- ChannelState.member(channel_state, nickname) do
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

  @spec current(ChannelState.t()) :: [Mode.t()]
  def current(channel_state) do
    Enum.flat_map(channel_state.modes, fn
      {:invite_only?, true} -> [:invite_only]
      {:moderated?, true} -> [:moderated]
      {:secret?, true} -> [:secret]
      {:protected_topic?, true} -> [:protected_topic]
      {:no_external_messages?, true} -> [:no_external_messages]
      {:channel_limit, limit} when not is_nil(limit) -> [{:channel_limit, limit}]
      {:key, key} when not is_nil(key) -> [{:key, key}]
      _ -> []
    end)
  end
end
