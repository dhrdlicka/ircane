defmodule IRCane.Protocol.Mode do
  @type t :: atom | {atom, term}

  @type mode_map :: %{
          char =>
            {:param_always | :param_when_set | :no_param, atom,
             [
               {:list, boolean}
               | {:parse, (String.t() -> {:ok, term} | :error)}
               | {:format, (term -> String.t())}
             ]}
        }

  @type mode_change :: {:add | :remove, t()}
  @type mode_list :: {:list, atom}
  @type invalid_mode :: {:invalid, {:unknown_mode, char} | {:invalid_param, atom, String.t()}}

  @spec parse([String.t()], mode_map) :: [mode_change() | mode_list() | invalid_mode()]
  def parse([mode_string | args], known_modes),
    do: parse(String.to_charlist(mode_string), args, known_modes, :add, [])

  defp parse(modes, args, known_modes, op, acc)

  defp parse([?+ | modes_tail], args, known_modes, _op, acc),
    do: parse(modes_tail, args, known_modes, :add, acc)

  defp parse([?- | modes_tail], args, known_modes, _op, acc),
    do: parse(modes_tail, args, known_modes, :remove, acc)

  defp parse([mode | modes_tail], args, known_modes, op, acc) do
    case {op, known_modes, args} do
      {op, %{^mode => {:param_always, name, opts}}, []} ->
        if opts[:list] do
          parse(modes_tail, args, known_modes, op, [{:list, name} | acc])
        else
          parse(modes_tail, args, known_modes, op, [{op, {name, nil}} | acc])
        end

      {op, %{^mode => {:param_always, name, _opts}}, [arg | args]} ->
        parse(modes_tail, args, known_modes, op, [{op, {name, arg}} | acc])

      {:add, %{^mode => {:param_when_set, name, _opts}}, []} ->
        parse(modes_tail, args, known_modes, op, [{:add, {name, nil}} | acc])

      {:add, %{^mode => {:param_when_set, name, _opts}}, [arg | args]} ->
        parse(modes_tail, args, known_modes, op, [{:add, {name, arg}} | acc])

      {:remove, %{^mode => {:param_when_set, name, _opts}}, _} ->
        parse(modes_tail, args, known_modes, op, [{:remove, name} | acc])

      {op, %{^mode => {:no_param, name, _opts}}, _} ->
        parse(modes_tail, args, known_modes, op, [{op, name} | acc])

      _ ->
        parse(modes_tail, args, known_modes, op, [{:invalid, {:unknown_mode, mode}} | acc])
    end
  end

  defp parse([], _args, _known_modes, _op, acc), do: Enum.reverse(acc)

  @spec parse_params([mode_change()], keyword()) :: [mode_change() | invalid_mode()]
  def parse_params(modes, known_modes) do
    known_modes = invert(known_modes)

    Enum.map(modes, fn
      {op, {name, arg}} ->
        {_letter, _type, opts} = known_modes[name]
        parse_fn = opts[:parse]

        if parse_fn do
          case parse_fn.(arg) do
            {:ok, parsed} -> {op, {name, parsed}}
            :error -> {:invalid, {:invalid_param, name, arg}}
          end
        else
          {op, {name, arg}}
        end

      other ->
        other
    end)
  end

  @spec build([mode_change()], mode_map) :: list(String.t())
  def build(modes, known_modes),
    do: build(modes, invert(known_modes), nil, {[], []})

  defp invert(modes),
    do:
      Enum.reduce(modes, %{}, fn
        {letter, {type, name, opts}}, acc -> Map.put(acc, name, {type, letter, opts})
      end)

  defp build([{:add, _} | _] = modes, known_modes, op, {mode_string, args}) when op != :add,
    do: build(modes, known_modes, :add, {[?+ | mode_string], args})

  defp build([{:remove, _} | _] = modes, known_modes, op, {mode_string, args})
       when op != :remove,
       do: build(modes, known_modes, :remove, {[?- | mode_string], args})

  defp build([{_op, {name, arg}} | modes], known_modes, op, {mode_string, args} = acc) do
    case known_modes do
      %{^name => {_, letter, _opts}} ->
        build(modes, known_modes, op, {[letter | mode_string], [arg | args]})

      _ ->
        build(modes, known_modes, op, acc)
    end
  end

  defp build([{_op, name} | modes], known_modes, op, {mode_string, args} = acc) do
    case known_modes do
      %{^name => {_, letter, _opts}} ->
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

  @spec format_params([mode_change()], keyword()) :: [mode_change()]
  def format_params(modes, known_modes) do
    known_modes = invert(known_modes)

    Enum.map(modes, fn
      {op, {name, arg}} when not is_binary(arg) ->
        {_letter, _type, opts} = known_modes[name]
        format_fn = opts[:format] || (&inspect/1)

        {op, {name, format_fn.(arg)}}

      other ->
        other
    end)
  end
end
