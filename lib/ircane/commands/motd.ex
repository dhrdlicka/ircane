defmodule IRCane.Commands.Motd do
  def handle(_params, _state) do
    {:error, :no_motd}
  end
end
