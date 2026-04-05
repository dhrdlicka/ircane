defmodule IRCane.Stats do
  use GenServer

  @type snapshot :: %{
          created_at: DateTime.t(),
          current_connections: non_neg_integer(),
          current_users: non_neg_integer(),
          peak_users: non_neg_integer(),
          current_channels: non_neg_integer(),
          peak_channels: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec snapshot() :: snapshot()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @spec created_at() :: DateTime.t()
  def created_at do
    GenServer.call(__MODULE__, :created_at)
  end

  @spec connection_opened() :: :ok
  def connection_opened do
    GenServer.cast(__MODULE__, :connection_opened)
  end

  @spec connection_closed() :: :ok
  def connection_closed do
    GenServer.cast(__MODULE__, :connection_closed)
  end

  @spec user_registered() :: :ok
  def user_registered do
    GenServer.cast(__MODULE__, :user_registered)
  end

  @spec user_unregistered() :: :ok
  def user_unregistered do
    GenServer.cast(__MODULE__, :user_unregistered)
  end

  @spec channel_created() :: :ok
  def channel_created do
    GenServer.cast(__MODULE__, :channel_created)
  end

  @spec channel_destroyed() :: :ok
  def channel_destroyed do
    GenServer.cast(__MODULE__, :channel_destroyed)
  end

  @impl true
  def init(_opts) do
    now = DateTime.utc_now()

    {:ok,
     %{
       created_at: now,
       current_connections: 0,
       current_users: 0,
       peak_users: 0,
       current_channels: 0,
       peak_channels: 0
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:created_at, _from, state) do
    {:reply, state.created_at, state}
  end

  @impl true
  def handle_cast(:connection_opened, state) do
    {:noreply, %{state | current_connections: state.current_connections + 1}}
  end

  @impl true
  def handle_cast(:connection_closed, state) do
    {:noreply, %{state | current_connections: max(0, state.current_connections - 1)}}
  end

  @impl true
  def handle_cast(:user_registered, state) do
    current_users = state.current_users + 1
    peak_users = max(state.peak_users, current_users)

    {:noreply, %{state | current_users: current_users, peak_users: peak_users}}
  end

  @impl true
  def handle_cast(:user_unregistered, state) do
    {:noreply, %{state | current_users: max(0, state.current_users - 1)}}
  end

  @impl true
  def handle_cast(:channel_created, state) do
    current_channels = state.current_channels + 1
    peak_channels = max(state.peak_channels, current_channels)

    {:noreply, %{state | current_channels: current_channels, peak_channels: peak_channels}}
  end

  @impl true
  def handle_cast(:channel_destroyed, state) do
    {:noreply, %{state | current_channels: max(0, state.current_channels - 1)}}
  end
end