defmodule IRCane.Commands.Motd do
  @moduledoc false
  def handle(_params, _state) do
    {:error, :no_motd}
  end
end
