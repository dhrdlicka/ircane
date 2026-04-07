defmodule IRCane.Channel.Membership do
  @moduledoc false
  alias IRCane.Channel.Role

  @enforce_keys [:nickname, :username, :hostname, :monitor_ref]
  defstruct nickname: nil,
            username: nil,
            hostname: nil,
            monitor_ref: nil,
            roles: []

  @type t ::
          %__MODULE__{
            nickname: String.t(),
            username: String.t(),
            hostname: String.t(),
            monitor_ref: reference(),
            roles: [Role.t()]
          }
end
