defmodule IRCane.Utils do
  @moduledoc false
  def parse_integer(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  @spec valid_channel_name?(String.t()) :: boolean()
  def valid_channel_name?(name) do
    cond do
      not String.starts_with?(name, ["#"]) -> false
      String.contains?(name, [" ", ",", "\a"]) -> false
      true -> true
    end
  end
end
