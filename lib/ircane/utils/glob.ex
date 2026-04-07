defmodule IRCane.Utils.Glob do
  @moduledoc """
  Implements IRC-style glob pattern matching
  """

  def match?(pattern, string) do
    do_match(String.to_charlist(pattern), String.to_charlist(string), nil)
  end

  def do_match([ph | pt], [sh | st], star) when ph == ?? or ph == sh do
    do_match(pt, st, star)
  end

  def do_match([?* | pt], s, _star) do
    do_match(pt, s, {pt, s})
  end

  def do_match(_p, _s, {pp, [_ | sst]}) do
    do_match(pp, sst, {pp, sst})
  end

  def do_match([], [], _star), do: true

  def do_match(p, [], _star) do
    Enum.all?(p, &(&1 == ?*))
  end

  def do_match(_, _, _), do: false
end
