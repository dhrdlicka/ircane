defmodule IRCane.ListenerSupervisor do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {IRCane.Listener, 6667}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
