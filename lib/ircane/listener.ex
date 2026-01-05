defmodule IRCane.Listener do
  alias IRCane.Client
  alias IRCane.ClientSupervisor

  require Logger

  def child_spec(port), do: Task.child_spec(fn -> listen(port) end)

  def listen(port) do
    opts = [
      :binary,
      packet: :raw,
      active: false,
      reuseaddr: true,
      backlog: 1024,
      nodelay: true,
      keepalive: true
    ]

    case :gen_tcp.listen(port, opts) do
      {:ok, socket} ->
        Logger.notice("IRC listener started on port #{port}")
        accept_loop(socket)

      {:error, reason} ->
        Logger.error("Failed to start listener on port #{port}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def accept_loop(listen_socket) do
    with {:ok, socket} <- :gen_tcp.accept(listen_socket),
         {:ok, {ip, port}} <- :inet.peername(socket),
         {:ok, pid} <- DynamicSupervisor.start_child(ClientSupervisor, {Client, socket}),
         :ok <- :gen_tcp.controlling_process(socket, pid) do
      Logger.debug("Accepted connection from #{:inet_parse.ntoa(ip)}:#{port}")
      Client.socket_ready(pid)
    else
      {:error, reason} ->
        Logger.error("Error accepting connection: #{inspect(reason)}")

      error ->
        Logger.error("Unexpected error in accept_loop: #{inspect(error)}")
    end

    accept_loop(listen_socket)
  end
end
