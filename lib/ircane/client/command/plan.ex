defmodule IRCane.Client.Command.Plan do
  @moduledoc false

  alias IRCane.Client.Command.Effects
  alias IRCane.Replies
  alias IRCane.User.State, as: UserState

  @enforce_keys [:state]
  defstruct state: nil,
            effects: [],
            replies: [],
            stop: nil

  @type t :: %__MODULE__{
          state: UserState.t(),
          effects: [Effects.effect()],
          replies: [Replies.reply()],
          stop: term() | nil
        }

  @spec new(UserState.t()) :: t()
  def new(proposed_state) do
    %__MODULE__{
      state: proposed_state
    }
  end

  @spec with_effect(t(), Effects.effect()) :: t()
  def with_effect(result, effect), do: with_effects(result, [effect])

  @spec with_effects(t(), [Effects.effect()]) :: t()
  def with_effects(result, effects) do
    %{result | effects: result.effects ++ effects}
  end

  @spec with_reply(t(), Replies.reply()) :: t()
  def with_reply(result, reply), do: with_replies(result, [reply])

  @spec with_replies(t(), [Replies.reply()]) :: t()
  def with_replies(result, replies) do
    %{result | replies: result.replies ++ replies}
  end

  @spec with_stop(t(), term()) :: t()
  def with_stop(result, reason) do
    %{result | stop: reason}
  end
end
