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

  @type parsed_mode :: mode_change() | mode_list() | invalid_mode()

  @spec parse([String.t()], mode_map) :: [parsed_mode()]
  def parse(mode_string, known_modes) do
    mode_string
    |> parse_modes(known_modes)
    |> parse_params(known_modes)
  end

  @spec parse_modes([String.t()], mode_map) :: [parsed_mode()]
  def parse_modes([mode_string | args], known_modes) do
    mode_string
    |> String.to_charlist()
    |> parse_modes(args, known_modes, :add, [])
  end

  defp parse_modes([?+ | modes_tail], args, known_modes, _op, acc),
    do: parse_modes(modes_tail, args, known_modes, :add, acc)

  defp parse_modes([?- | modes_tail], args, known_modes, _op, acc),
    do: parse_modes(modes_tail, args, known_modes, :remove, acc)

  defp parse_modes([mode | modes_tail], args, known_modes, op, acc) do
    case {op, known_modes, args} do
      {op, %{^mode => {:param_always, name, opts}}, []} ->
        if opts[:list] do
          parse_modes(modes_tail, args, known_modes, op, [{:list, name} | acc])
        else
          parse_modes(modes_tail, args, known_modes, op, [{:invalid, {:no_param, name}} | acc])
        end

      {op, %{^mode => {:param_always, name, _opts}}, [arg | args]} ->
        parse_modes(modes_tail, args, known_modes, op, [{op, {name, arg}} | acc])

      {:add, %{^mode => {:param_when_set, name, _opts}}, []} ->
        parse_modes(modes_tail, args, known_modes, op, [{:invalid, {:no_param, name}} | acc])

      {:add, %{^mode => {:param_when_set, name, _opts}}, [arg | args]} ->
        parse_modes(modes_tail, args, known_modes, op, [{:add, {name, arg}} | acc])

      {:remove, %{^mode => {:param_when_set, name, _opts}}, _} ->
        parse_modes(modes_tail, args, known_modes, op, [{:remove, name} | acc])

      {op, %{^mode => {:no_param, name, _opts}}, _} ->
        parse_modes(modes_tail, args, known_modes, op, [{op, name} | acc])

      _ ->
        parse_modes(modes_tail, args, known_modes, op, [{:invalid, {:unknown_mode, mode}} | acc])
    end
  end

  defp parse_modes([], _args, _known_modes, _op, acc), do: Enum.reverse(acc)

  @spec parse_params([parsed_mode()], mode_map()) :: [parsed_mode()]
  def parse_params(modes, known_modes) do
    known_modes = invert(known_modes)

    Enum.map(modes, fn
      {op, {name, arg}} when op in [:add, :remove] ->
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

  @spec format([mode_change()], mode_map) :: [String.t()]
  def format(modes, known_modes) do
    modes
    |> format_params(known_modes)
    |> format_modes(known_modes)
  end

  @spec format_modes([mode_change()], mode_map) :: list(String.t())
  def format_modes(modes, known_modes),
    do: format_modes(modes, invert(known_modes), nil, {[], []})

  defp invert(modes),
    do:
      Enum.reduce(modes, %{}, fn
        {letter, {type, name, opts}}, acc -> Map.put(acc, name, {type, letter, opts})
      end)

  defp format_modes([{:add, _} | _] = modes, known_modes, op, {mode_string, args})
       when op != :add,
       do: format_modes(modes, known_modes, :add, {[?+ | mode_string], args})

  defp format_modes([{:remove, _} | _] = modes, known_modes, op, {mode_string, args})
       when op != :remove,
       do: format_modes(modes, known_modes, :remove, {[?- | mode_string], args})

  defp format_modes([{_op, {name, arg}} | modes], known_modes, op, {mode_string, args} = acc) do
    case known_modes do
      %{^name => {_, letter, _opts}} ->
        format_modes(modes, known_modes, op, {[letter | mode_string], [arg | args]})

      _ ->
        format_modes(modes, known_modes, op, acc)
    end
  end

  defp format_modes([{_op, name} | modes], known_modes, op, {mode_string, args} = acc) do
    case known_modes do
      %{^name => {_, letter, _opts}} ->
        format_modes(modes, known_modes, op, {[letter | mode_string], args})

      _ ->
        format_modes(modes, known_modes, op, acc)
    end
  end

  defp format_modes([], _known_modes, _op, {[char], []}) when char in ~c"+-", do: [""]

  defp format_modes([], _known_modes, _op, {mode_string, args}) do
    modes =
      mode_string
      |> Enum.reverse()
      |> List.to_string()

    [modes | Enum.reverse(args)]
  end

  @spec format_params([mode_change()], mode_map()) :: [mode_change()]
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
