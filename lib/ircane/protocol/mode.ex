defmodule IRCane.Protocol.Mode do
  @type t :: atom | {atom, String.t()}

  @type mode_type :: :type_a | :type_b | :type_c | :type_d

  @type mode_map :: %{
          char => {mode_type, atom}
        }

  @type invalid_reason :: {:unknown_mode, char} | {:invalid_param, atom, String.t()}

  @spec parse(list(String.t()), mode_map) :: list({:add | :remove | :list, t} | {:invalid, invalid_reason})
  def parse([mode_string | args], known_modes),
    do: parse(String.to_charlist(mode_string), args, known_modes, :add, [])

  defp parse(modes, args, known_modes, op, acc)

  defp parse([?+ | modes_tail], args, known_modes, _op, acc),
    do: parse(modes_tail, args, known_modes, :add, acc)

  defp parse([?- | modes_tail], args, known_modes, _op, acc),
    do: parse(modes_tail, args, known_modes, :remove, acc)

  defp parse([mode | modes_tail], args, known_modes, op, acc) do
    case {op, known_modes, args} do
      {op, %{^mode => {:type_a, name}}, []} ->
        parse(modes_tail, [], known_modes, op, [{:list, name} | acc])

      {op, %{^mode => {:type_a, name}}, [arg | args]} ->
        parse(modes_tail, args, known_modes, op, [{op, {name, arg}} | acc])

      {op, %{^mode => {:type_b, name}}, []} ->
        parse(modes_tail, args, known_modes, op, [{op, {name, nil}} | acc])

      {op, %{^mode => {:type_b, name}}, [arg | args]} ->
        parse(modes_tail, args, known_modes, op, [{op, {name, arg}} | acc])

      {:add, %{^mode => {:type_c, name}}, []} ->
        parse(modes_tail, args, known_modes, op, [{:add, {name, nil}} | acc])

      {:add, %{^mode => {:type_c, name}}, [arg | args]} ->
        parse(modes_tail, args, known_modes, op, [{:add, {name, arg}} | acc])

      {:remove, %{^mode => {:type_c, name}}, _} ->
        parse(modes_tail, args, known_modes, op, [{:remove, name} | acc])

      {op, %{^mode => {:type_d, name}}, _} ->
        parse(modes_tail, args, known_modes, op, [{op, name} | acc])

      _ ->
        parse(modes_tail, args, known_modes, op, [{:invalid, {:unknown_mode, mode}} | acc])
    end
  end

  defp parse([], _args, _known_modes, _op, acc), do: Enum.reverse(acc)

  @spec parse_params(list({atom(), t}), keyword()) :: list({atom(), t})
  def parse_params(modes, opts) do
    Enum.map(modes, fn
      {op, {name, arg}} when is_map_key(opts, name) ->
        with parse_fn = Keyword.get(opts[name], :parse, &(&1)),
             {:ok, parsed} <- parse_fn.(arg) do
          {op, {name, parsed}}
        else
          _ ->
            {:invalid, {:invalid_param, name, arg}}
        end
      other ->
        other
    end)
  end

  @spec build(list({:add | :remove, t}), mode_map) :: list(String.t())
  def build(modes, known_modes),
    do: build(modes, invert(known_modes), nil, {[], []})

  defp invert(modes),
    do:
      Enum.reduce(modes, %{}, fn
        {letter, {type, name}}, acc -> Map.put(acc, name, {type, letter})
      end)

  defp build([{:add, _} | _] = modes, known_modes, op, {mode_string, args}) when op != :add,
    do: build(modes, known_modes, :add, {[?+ | mode_string], args})

  defp build([{:remove, _} | _] = modes, known_modes, op, {mode_string, args})
       when op != :remove,
       do: build(modes, known_modes, :remove, {[?- | mode_string], args})

  defp build([{_op, {name, arg}} | modes], known_modes, op, {mode_string, args} = acc) do
    case known_modes do
      %{^name => {_, letter}} ->
        build(modes, known_modes, op, {[letter | mode_string], [arg | args]})

      _ ->
        build(modes, known_modes, op, acc)
    end
  end

  defp build([{_op, name} | modes], known_modes, op, {mode_string, args} = acc) do
    case known_modes do
      %{^name => {_, letter}} ->
        build(modes, known_modes, op, {[letter | mode_string], args})

      _ ->
        build(modes, known_modes, op, acc)
    end
  end

  defp build([], _known_modes, _op, {[char], []}) when char in ~c"+-", do: [""]

  defp build([], _known_modes, _op, {mode_string, args}) do
    modes =
      mode_string
      |> Enum.reverse()
      |> List.to_string()

    [modes | Enum.reverse(args)]
  end

  @spec format_params(list({atom(), t}), keyword()) :: list({atom(), t})
  def format_params(modes, opts) do
    Enum.map(modes, fn
      {op, {name, arg}} when is_map_key(opts, name) ->
        format_fn = Keyword.get(opts[name], :format, &inspect/1)
        {op, {name, format_fn.(arg)}}
      other ->
        other
    end)
  end
end
