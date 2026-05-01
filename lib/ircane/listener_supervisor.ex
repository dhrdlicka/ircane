defmodule IRCane.ListenerSupervisor do
  @moduledoc false
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def listeners do
    :ircane
    |> Application.get_env(:listeners, [])
    |> normalize_listeners()
  end

  def child_specs do
    child_specs(listeners())
  end

  def child_specs(listener_child_specs) when is_list(listener_child_specs) do
    listener_child_specs
  end

  @impl true
  def init(opts) do
    listener_child_specs = if opts == [], do: listeners(), else: opts
    Supervisor.init(child_specs(listener_child_specs), strategy: :one_for_one)
  end

  defp normalize_listeners(nil), do: []

  defp normalize_listeners(listener_child_specs) when is_list(listener_child_specs),
    do: listener_child_specs
end
