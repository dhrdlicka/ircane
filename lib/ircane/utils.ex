defmodule IRCane.Utils do
  @moduledoc false
  def parse_integer(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end
end
