defmodule IRCane.Protocol.Message do
  @moduledoc false
  defstruct source: nil,
            command: nil,
            params: []

  @type t :: %__MODULE__{
          source: nil | source,
          command: command,
          params: params
        }

  @type source :: String.t() | {String.t(), String.t(), String.t()}
  @type command :: String.t()
  @type params :: [String.t()]

  @typep message :: String.t()

  @spec new(source :: source | map | nil, command :: command, params :: params) :: t
  def new(%{username: username, hostname: hostname, nickname: nickname}, command, params) do
    new({nickname, username, hostname}, command, params)
  end

  def new(source, command, params) do
    %__MODULE__{source: source, command: command, params: params}
  end

  @spec new(command :: command, params :: params) :: t
  def new(command, params) do
    new(nil, command, params)
  end

  @spec parse(message) :: {:ok, t()} | {:error, atom()}
  def parse(":" <> message) do
    with [source, message] <- String.split(message, " ", parts: 2, trim: true),
         {:ok, %__MODULE__{} = message} <- parse(message) do
      source =
        with [nickname, source] <- String.split(source, "!"),
             [username, hostname] <- String.split(source, "@") do
          {nickname, username, hostname}
        else
          _ -> source
        end

      {:ok, %__MODULE__{message | source: source}}
    else
      _ -> {:error, :invalid_message}
    end
  end

  def parse(message) do
    with [params | trailing] <- message |> String.trim() |> String.split(" :", parts: 2),
         [command | params] <- String.split(params) do
      {:ok, %__MODULE__{command: command, params: params ++ trailing}}
    else
      _ ->
        {:error, :invalid_message}
    end
  end

  @spec format(t) :: message
  def format(%__MODULE__{source: {nickname, username, hostname}} = message) do
    format(%{message | source: "#{nickname}!#{username}@#{hostname}"})
  end

  def format(%__MODULE__{source: source, command: command, params: params}) when source != nil do
    format(":#{source} #{command}", params)
  end

  def format(%__MODULE__{command: command, params: params}) do
    format("#{command}", params)
  end

  defp format(message, []), do: message

  defp format(message, [trailing]) do
    if String.contains?("#{trailing}", [" ", ":"]) do
      "#{message} :#{trailing}"
    else
      "#{message} #{trailing}"
    end
  end

  defp format(message, ["" | params]),
    do: format(message, params)

  defp format(message, [param | params]) do
    format("#{message} #{param}", params)
  end
end
