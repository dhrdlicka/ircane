defmodule IRCane.Client.Command.Handlers.Topic do
  @moduledoc false

  alias IRCane.Client.Command.Plan

  @behaviour IRCane.Client.Command.Handler

  def handle([channel_name], state) do
    state
    |> Plan.new()
    |> Plan.with_effect({:get_channel_topic, channel_name})
    |> then(&{:ok, &1})
  end

  def handle([channel_name | topic_parts], state) do
    topic = Enum.join(topic_parts, " ")

    state
    |> Plan.new()
    |> Plan.with_effect({:update_channel_topic, channel_name, topic})
    |> then(&{:ok, &1})
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "TOPIC"}}
  end
end
