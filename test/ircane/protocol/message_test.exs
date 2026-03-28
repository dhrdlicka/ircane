defmodule IRCane.Protocol.MessageTest do
  use ExUnit.Case

  alias IRCane.Protocol.Message

  describe "new/3" do
    test "creates a message with a source, command and params" do
      source = {"nick", "user", "host"}
      command = "TEST"
      params = ["foo", "bar"]

      assert %Message{source: ^source, command: ^command, params: ^params} =
               Message.new(source, command, params)
    end

    test "creates a message with a map as source" do
      source = %{nickname: "nick", username: "user", hostname: "host"}
      command = "TEST"
      params = ["foo", "bar"]

      assert %Message{source: {"nick", "user", "host"}, command: ^command, params: ^params} =
               Message.new(source, command, params)
    end
  end

  describe "new/2" do
    test "creates a message with a command and params" do
      command = "TEST"
      params = ["foo", "bar"]

      assert %Message{source: nil, command: ^command, params: ^params} =
               Message.new(command, params)
    end
  end

  describe "parse/1" do
    test "parses a command with no params" do
      assert {:ok, %Message{command: "TEST", params: []}} =
               Message.parse("TEST")
    end

    test "parses params" do
      assert {:ok, %Message{command: "TEST", params: ["foo", "bar"]}} =
               Message.parse("TEST foo bar")
    end

    test "parses a trailing param" do
      assert {:ok, %Message{command: "TEST", params: ["foo", "bar", "hello world!"]}} =
               Message.parse("TEST foo bar :hello world!")
    end

    test "parses a trailing parameter with colons" do
      assert {:ok, %Message{command: "TEST", params: ["foo", "bar", "hello :D"]}} =
               Message.parse("TEST foo bar :hello :D")
    end

    test "parses the source hostmask into a tuple" do
      assert {:ok,
              %Message{source: {"nick", "user", "host"}, command: "TEST", params: ["foo", "bar"]}} =
               Message.parse(":nick!user@host TEST foo bar")
    end

    test "parses the source if it's not a hostmask" do
      assert {:ok, %Message{source: "source", command: "TEST", params: ["foo", "bar"]}} =
               Message.parse(":source TEST foo bar")
    end

    test "preserves spaces in the trailing parameter" do
      assert {:ok, %Message{command: "TEST", params: ["    four spaces"]}} =
               Message.parse("TEST :    four spaces")
    end

    test "returns error if the message only has a source" do
      assert {:error, _} = Message.parse(":source")
    end

    test "returns error if the message is empty" do
      assert {:error, _} = Message.parse("")
    end
  end

  describe "build/2" do
    test "builds a message with a command" do
      message = %Message{command: "TEST"}

      assert "TEST" = Message.format(message)
    end

    test "builds a message with a command and params" do
      message = %Message{command: "TEST", params: ["foo", "bar"]}

      assert "TEST foo bar" = Message.format(message)
    end

    test "builds a message with a source and command" do
      message = %Message{source: "source", command: "TEST"}

      assert ":source TEST" = Message.format(message)
    end

    test "builds a message with a source, command and params" do
      message = %Message{source: "source", command: "TEST", params: ["foo", "bar"]}

      assert ":source TEST foo bar" = Message.format(message)
    end

    test "escapes spaces in the last parameter" do
      message = %Message{command: "TEST", params: ["hello world!"]}

      assert "TEST :hello world!" = Message.format(message)
    end

    test "escapes colons in the last parameter" do
      message = %Message{command: "TEST", params: [":D"]}

      assert "TEST ::D" = Message.format(message)
    end

    test "skips empty strings in params" do
      message = %Message{command: "TEST", params: ["foo", "", "bar"]}

      assert "TEST foo bar" = Message.format(message)
    end

    test "handles hostmask tuple as source" do
      message = %Message{source: {"nick", "user", "host"}, command: "TEST"}

      assert ":nick!user@host TEST" = Message.format(message)
    end
  end
end
