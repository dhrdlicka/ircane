defmodule IRCane.Channel.Membership do
  defstruct nickname: nil,
            operator?: false,
            voice?: false

  @type t ::
          %__MODULE__{
            nickname: String.t(),
            operator?: boolean(),
            voice?: boolean()
          }
end
