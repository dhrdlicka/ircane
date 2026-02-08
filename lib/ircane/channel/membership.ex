defmodule IRCane.Channel.Membership do
  alias IRCane.Channel.Role

  defstruct nickname: nil,
            roles: []

  @type t ::
          %__MODULE__{
            nickname: String.t(),
            roles: [Role.t()]
          }
end
