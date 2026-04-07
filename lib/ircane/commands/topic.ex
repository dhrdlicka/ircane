defmodule IRCane.Commands.Topic do
  @moduledoc false
  alias IRCane.Channel

  require Logger

  def handle([channel_name], state) do
    with {:ok, {channel_name, topic}} <- Channel.topic(channel_name) do
      {:ok, {:topic, channel_name, topic}, state}
    end
  end

  def handle([channel_name | topic_parts], state) do
    topic = Enum.join(topic_parts, " ")

    with :ok <- Channel.update_topic(channel_name, state, topic) do
      {:ok, {:topic, state, channel_name, topic}, state}
    end
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "TOPIC"}}
  end
end
