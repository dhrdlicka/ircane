defmodule IRCane.Client.Command.Handlers.Notice do
  @moduledoc false

  alias IRCane.Client.Command.Plan
  alias IRCane.User.State, as: UserState

  require Logger

  @behaviour IRCane.Client.Command.Handler

  def handle([targets, message | message_parts], state) do
    message = Enum.join([message | message_parts], " ")

    {unique_targets, self} =
      targets
      |> String.split(",")
      |> Enum.uniq_by(&String.downcase/1)
      |> Enum.split_with(&(String.downcase(&1) != String.downcase(state.nickname)))

    {channels, users} =
      Enum.split_with(unique_targets, fn target -> String.starts_with?(target, "#") end)

    state
    |> UserState.update_idle()
    |> Plan.new()
    |> Plan.with_effects(Enum.map(users, &{:send_user_notice, &1, message}))
    |> Plan.with_effects(Enum.map(channels, &{:send_channel_notice, &1, message}))
    |> Plan.with_replies(Enum.map(self, fn _ -> {:notice, state, state.nickname, message} end))
    |> then(&{:ok, &1})
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "NOTICE"}}
  end
end
