defmodule IRCane.BanMask do
  @moduledoc false
  alias IRCane.Utils.Glob

  def parse(mask) do
    with [nick, rest] <- String.split(mask, "!", parts: 2),
         [user, host] <- String.split(rest, "@", parts: 2) do
      {:ok, {nick, user, host}}
    else
      _ -> :error
    end
  end

  def format({nick, user, host}) do
    "#{nick}!#{user}@#{host}"
  end

  def match?({nick_mask, user_mask, host_mask}, %{nickname: nick, username: user, hostname: host}) do
    Glob.match?(nick_mask, nick) and Glob.match?(user_mask, user) and Glob.match?(host_mask, host)
  end
end
