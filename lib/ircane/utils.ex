defmodule IRCane.Utils do
  def parse_integer(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end
end
