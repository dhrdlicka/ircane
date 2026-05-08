defmodule IRCane.Client.SessionState do
  @moduledoc false

  defstruct seen_events: :queue.new(),
            connected_at_mono: nil,
            last_rx_mono: nil,
            ping_sent_at_mono: nil

  @type t :: %__MODULE__{
          seen_events: :queue.queue(),
          connected_at_mono: non_neg_integer() | nil,
          last_rx_mono: non_neg_integer() | nil,
          ping_sent_at_mono: non_neg_integer() | nil
        }

  @event_dedup_size Application.compile_env!(:ircane, :event_dedup_size)

  @spec new() :: t()
  def new do
    %__MODULE__{connected_at_mono: System.monotonic_time(:millisecond)}
  end

  @spec heartbeat_action(t(), boolean()) ::
          {{:disconnect, :ping_timeout | :registration_timeout} | :send_ping | :noop, t()}
  def heartbeat_action(%{connected_at_mono: connected_at_mono} = state, false = _registered?) do
    now = System.monotonic_time(:millisecond)
    diff = now - connected_at_mono

    if diff > registration_timeout_msec() do
      {{:disconnect, :registration_timeout}, state}
    else
      {:noop, state}
    end
  end

  def heartbeat_action(
        %{ping_sent_at_mono: nil, last_rx_mono: last_rx_mono} = state,
        _registered?
      ) do
    now = System.monotonic_time(:millisecond)
    diff = now - last_rx_mono

    if diff > ping_timeout_msec() do
      {:send_ping, %{state | ping_sent_at_mono: now}}
    else
      {:noop, state}
    end
  end

  def heartbeat_action(%{ping_sent_at_mono: ping_sent_at_mono} = state, _registered?) do
    now = System.monotonic_time(:millisecond)
    diff = now - ping_sent_at_mono

    if diff > ping_timeout_msec() do
      {{:disconnect, :ping_timeout}, state}
    else
      {:noop, state}
    end
  end

  @spec update_last_rx_mono(t()) :: t()
  def update_last_rx_mono(state) do
    %{state | last_rx_mono: System.monotonic_time(:millisecond), ping_sent_at_mono: nil}
  end

  @spec try_push_event(t(), term()) :: {:ok, t()} | :noop
  def try_push_event(%{seen_events: seen_events} = state, event_ref) do
    cond do
      :queue.member(event_ref, state.seen_events) ->
        :noop

      :queue.len(seen_events) >= @event_dedup_size ->
        {_, queue} = :queue.out(seen_events)
        {:ok, %{state | seen_events: :queue.in(event_ref, queue)}}

      true ->
        {:ok, %{state | seen_events: :queue.in(event_ref, seen_events)}}
    end
  end

  defp registration_timeout_msec, do: Application.fetch_env!(:ircane, :registration_timeout_msec)
  defp ping_timeout_msec, do: Application.fetch_env!(:ircane, :ping_timeout_msec)
end
