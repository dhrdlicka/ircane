defmodule IRCane.Command.Plan do
  @moduledoc false

  alias IRCane.User.State, as: UserState

  @enforce_keys [:state]
  defstruct state: nil,
            effects: [],
            replies: []

  @type effect :: term()
  @type reply :: term()

  @type t :: %__MODULE__{
          state: UserState.t(),
          effects: [effect()],
          replies: [reply()]
        }

  @spec new(UserState.t()) :: t()
  def new(proposed_state) do
    %__MODULE__{
      state: proposed_state
    }
  end

  @spec with_effect(t(), effect()) :: t()
  def with_effect(result, effect), do: with_effects(result, [effect])

  @spec with_effects(t(), [effect()]) :: t()
  def with_effects(result, effects) do
    %{result | effects: result.effects ++ effects}
  end

  @spec with_reply(t(), reply()) :: t()
  def with_reply(result, reply), do: with_replies(result, [reply])

  @spec with_replies(t(), [reply()]) :: t()
  def with_replies(result, replies) do
    %{result | replies: result.replies ++ replies}
  end
end
