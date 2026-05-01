defmodule IRCane.TestFactory do
  alias IRCane.Channel.Membership
  alias IRCane.Channel.Topic
  alias IRCane.User.State, as: UserState

  @spec build(atom(), keyword()) :: struct() | pid()
  def build(name, attrs \\ [])

  def build(:pid, _attrs) do
    spawn(fn -> :ok end)
  end

  def build(name, attrs) when is_atom(name) and is_list(attrs) do
    merged_attrs =
      name
      |> defaults()
      |> Enum.into(%{})
      |> Map.merge(Enum.into(attrs, %{}))

    struct!(module(name), merged_attrs)
  end

  defp module(:membership), do: Membership
  defp module(:topic), do: Topic
  defp module(:user_state), do: UserState

  defp defaults(:membership) do
    [
      nickname: "nick",
      username: "user",
      hostname: "host",
      monitor_ref: make_ref(),
      roles: []
    ]
  end

  defp defaults(:topic) do
    [
      topic: "topic",
      set_by: "nick",
      set_at: DateTime.utc_now()
    ]
  end

  defp defaults(:user_state) do
    [
      pid: self(),
      nickname: "nick",
      username: "user",
      hostname: "host"
    ]
  end
end
