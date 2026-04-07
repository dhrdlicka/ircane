defmodule IRCane.User.ChannelMembership do
  @moduledoc false
  alias IRCane.Channel.Role

  @enforce_keys [:name, :monitor_ref]
  defstruct name: nil,
            monitor_ref: nil,
            roles: []

  @type t :: %__MODULE__{
          name: String.t(),
          monitor_ref: reference(),
          roles: [Role.t()]
        }
end
