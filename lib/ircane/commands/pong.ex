defmodule IRCane.Commands.Pong do
  @moduledoc false

  def handle([_token | _], state) do
    {:ok, state}
  end

  def handle(_, _state) do
    {:error, :need_more_params}
  end
end
