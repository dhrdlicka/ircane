defmodule IRCane.Command.Runner do
  @moduledoc false

  alias IRCane.Command.Effects
  alias IRCane.Command.Plan
  alias IRCane.Replies
  alias IRCane.User.State, as: UserState

  @spec run(Plan.t()) :: {:ok, [Replies.reply()], UserState.t()} | {:error, Replies.reply()}
  def run(%Plan{} = plan) do
    Enum.reduce_while(plan.effects, {:ok, plan.replies, plan.state}, fn effect,
                                                                        {:ok, replies, state} ->
      case Effects.execute(state, effect) do
        {:ok, new_state} -> {:cont, {:ok, replies, new_state}}
        {:ok, new_state, new_replies} -> {:cont, {:ok, replies ++ new_replies, new_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
