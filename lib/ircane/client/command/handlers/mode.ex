defmodule IRCane.Client.Command.Handlers.Mode do
  @moduledoc false
  alias IRCane.Client.Command.Plan
  alias IRCane.Protocol.Mode
  alias IRCane.User.State, as: UserState

  @behaviour IRCane.Client.Command.Handler

  @user_modes Application.compile_env!(:ircane, :user_modes)
  @channel_modes Application.compile_env!(:ircane, :channel_modes)

  def handle(["#" <> _ = target | []], state) do
    state
    |> Plan.new()
    |> Plan.with_effect({:get_channel_mode, target})
    |> then(&{:ok, &1})
  end

  def handle([target | []], state) do
    if String.downcase(target) == String.downcase(state.nickname) do
      state
      |> Plan.new()
      |> Plan.with_reply({:umode_is, UserState.mode(state)})
      |> then(&{:ok, &1})
    else
      {:error, :users_dont_match}
    end
  end

  def handle(["#" <> _ = target | params], state) do
    {changes, lists, invalid} = parse_modes(params, @channel_modes)

    errors =
      Enum.map(invalid, fn
        {:unknown_mode, char} ->
          {:unknown_mode, char}

        {:invalid_param, mode, param} ->
          {char, _mode_def} =
            Enum.find(@channel_modes, fn {_char, {_type, name, _opts}} -> name == mode end)

          {:invalid_mode_param, target, char, param}
      end)

    state
    |> Plan.new()
    |> Plan.with_effect({:update_channel_mode, target, changes})
    |> Plan.with_effects(Enum.map(lists, &{:get_channel_mode_list, target, &1}))
    |> Plan.with_replies(errors)
    |> then(&{:ok, &1})
  end

  def handle([target | params], state) do
    {changes, _lists, invalid} = parse_modes(params, @user_modes)

    errors =
      Enum.map(invalid, fn
        {:unknown_mode, _char} ->
          :umode_unknown_flag

        {:invalid_param, mode, param} ->
          {char, _mode_def} =
            Enum.find(@user_modes, fn {_char, {_type, name, _opts}} -> name == mode end)

          {:invalid_mode_param, target, char, param}
      end)

    if String.downcase(target) == String.downcase(state.nickname) do
      with {:ok, new_state, replies} <- apply_user_mode(state, changes) do
        new_state
        |> Plan.new()
        |> Plan.with_replies(errors)
        |> Plan.with_replies(replies)
        |> then(&{:ok, &1})
      end
    else
      {:error, :users_dont_match}
    end
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "MODE"}}
  end

  defp parse_modes(mode_strings, valid_modes) do
    modes =
      mode_strings
      |> Mode.parse(valid_modes)
      |> Enum.group_by(
        fn
          {:add, _} -> :changes
          {:remove, _} -> :changes
          {:list, _} -> :lists
          {:invalid, _} -> :invalid
        end,
        fn
          {:add, mode} -> {:add, mode}
          {:remove, mode} -> {:remove, mode}
          {:list, mode} -> mode
          {:invalid, reason} -> reason
        end
      )

    {modes[:changes] || [], Enum.uniq(modes[:lists] || []), Enum.uniq(modes[:invalid] || [])}
  end

  defp apply_user_mode(state, mode_changes) do
    with {:ok, new_state, applied, errors} <- UserState.update_mode(state, mode_changes) do
      user_mode_reply =
        if applied != [],
          do: [{:user_mode, state, state.nickname, applied}],
          else: []

      {:ok, new_state, user_mode_reply ++ errors}
    end
  end
end
