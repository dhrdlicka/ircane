defmodule IRCane.Commands.Mode do
  alias IRCane.Protocol.Mode
  alias IRCane.Channel

  @channel_modes Application.compile_env!(:ircane, :channel_modes)
  @mode_opts Application.compile_env!(:ircane, :mode_opts)

  def handle(["#" <> _ = target | []], state) do
    with {:ok, {channel_name, modes}} <- Channel.mode(target) do
      {:ok, {:channel_mode_is, channel_name, modes}, state}
    end
  end

  def handle(["#" <> _ = target | params], state) do
    modes =
      params
      |> Mode.parse(@channel_modes)
      |> Mode.parse_params(@mode_opts)

    {mode_changes, lists, invalid} =
      Enum.reduce(modes, {[], [], []}, fn
        {:add, _} = op, {x, y, z} -> {[op | x], y, z}
        {:remove, _} = op, {x, y, z} -> {[op | x], y, z}
        {:list, mode}, {x, y, z} -> {x, [mode | y], z}
        {:invalid, reason}, {x, y, z} -> {x, y, [reason | z]}
      end)

    unknown_modes =
      invalid
      |> Enum.filter(fn {:unknown_mode, _} -> true; _ -> false end)
      |> Enum.uniq()

    lists =
      lists
      |> Enum.uniq()
      |> Enum.map(&list(target, &1))

    {mode, errors} =
      case Channel.update_mode(target, mode_changes, state) do
        {:ok, {_name, [], errors}} ->
          {nil, errors}

        {:ok, {name, applied_changes, errors}} ->
          {{:channel_mode, state, name, applied_changes}, errors}

        {:error, reason} ->
          {nil, [reason]}
      end

    replies = unknown_modes ++ lists ++ errors ++ (if mode, do: [mode], else: [])

    {:ok, replies, state}
  end

  def handle([_target | []], state) do
    {:ok, state}
  end

  def handle([_target | _params], state) do
    {:ok, state}
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "MODE"}}
  end

  defp list(target, :ban) do
    {:ban_list, target, []}
  end
end
