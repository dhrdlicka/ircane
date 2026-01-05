defmodule IRCane.Message do
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

  @spec build(t) :: message
  def build(%__MODULE__{source: {nickname, username, hostname}} = message) do
    build(%{message | source: "#{nickname}!#{username}@#{hostname}"})
  end

  def build(%__MODULE__{source: source, command: command, params: params}) when source != nil do
    build(":#{source} #{command}", params)
  end

  def build(%__MODULE__{command: command, params: params}) do
    build("#{command}", params)
  end

  defp build(message, []), do: message

  defp build(message, [trailing]) do
    if String.contains?("#{trailing}", [" ", ":"]) do
      "#{message} :#{trailing}"
    else
      "#{message} #{trailing}"
    end
  end

  defp build(message, ["" | params]),
    do: build(message, params)

  defp build(message, [param | params]) do
    build("#{message} #{param}", params)
  end
end
