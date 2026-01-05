defmodule IRCane.Commands.Topic do
  alias IRCane.Channel
  alias IRCane.ChannelRegistry

  require Logger

  def handle([channel_name], state) do
    case Registry.lookup(ChannelRegistry, String.downcase(channel_name)) do
      [{pid, _}] ->
        with {:ok, {channel_name, topic}} <- Channel.topic(pid) do
          {:ok, {:topic, channel_name, topic}, state}
        end

      [] ->
        {:error, {:no_such_channel, channel_name}}
    end
  end

  def handle([channel_name | topic_parts], state) do
    topic = Enum.join(topic_parts, " ")

    case Registry.lookup(ChannelRegistry, String.downcase(channel_name)) do
      [{pid, channel_name}] ->
        with :ok <- Channel.topic(pid, state, topic) do
          {:ok, {:topic, state, channel_name, topic}, state}
        end

      [] ->
        {:error, {:no_such_channel, channel_name}}
    end
  end

  def handle(_, _state) do
    {:error, {:need_more_params, "TOPIC"}}
  end
end
