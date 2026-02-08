defmodule IRCane.Channel.Role do
  @type t :: atom()

  @roles Application.compile_env!(:ircane, :roles)

  @spec max([t()]) :: t() | nil
  def max(roles) when is_list(roles) do
    Enum.max_by(roles, &rank/1, fn -> nil end)
  end

  @spec compare(t(), t()) :: integer()
  def compare(role1, role2) do
    rank(role1) - rank(role2)
  end

  @spec highest_target(t()) :: t()
  def highest_target(role) do
    Keyword.get(@roles, role, %{})[:highest_target] || role
  end

  @spec prefix(t()) :: String.t()
  def prefix(role) do
    prefix = Keyword.get(@roles, role, %{})[:prefix]
    if prefix, do: <<prefix::utf8>>, else: ""
  end

  defp rank(role) when is_atom(role) do
    case Enum.find_index(@roles, fn {r, _} -> r == role end) do
      nil -> 0
      index -> index + 1
    end
  end
end
