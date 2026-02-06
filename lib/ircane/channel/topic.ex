defmodule IRCane.Channel.Topic do
  defstruct topic: nil,
            set_by: nil,
            set_at: nil

  @type t ::
          %__MODULE__{
            topic: String.t(),
            set_by: String.t(),
            set_at: DateTime.t()
          }
end
