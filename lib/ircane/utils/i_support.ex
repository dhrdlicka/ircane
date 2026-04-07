defmodule IRCane.Utils.ISupport do
  @channel_modes Application.compile_env(:ircane, :channel_modes)
  @roles Application.compile_env(:ircane, :roles)
  @network_name Application.compile_env(:ircane, :network_name)

  def build_chanmodes() do
    %{type_a: modes_a, type_b: modes_b, type_c: modes_c, type_d: modes_d} =
      @channel_modes
      |> Enum.group_by(fn {_letter, {type, name, opts}} ->
        case {type, opts[:list], @roles[name]} do
          {_, _, role} when not is_nil(role) -> :prefix
          {:param_always, true, _} -> :type_a
          {:param_always, _, _} -> :type_b
          {:param_when_set, _, _} -> :type_c
          {:no_param, _, _} -> :type_d
        end
      end)
      |> Map.new()

    Enum.map_join([modes_a, modes_b, modes_c, modes_d], ",", &Enum.map(&1, fn {letter, {_type, _name, _opts}} -> letter end))
  end

  def build_prefix() do
    {modes, prefixes} =
      @roles
      |> Enum.reverse()
      |> Enum.map(fn {role, %{prefix: prefix}} ->
        mode =
          Enum.find_value(@channel_modes, nil, fn
            {letter, {_type, ^role, _opts}} -> letter
            _ -> nil
          end)

        {mode, prefix}
      end)
      |> Enum.filter(fn {mode, _prefix} -> mode end)
      |> Enum.unzip()

    "(#{modes})#{prefixes}"
  end

  def build() do
    %{
      casemapping: "ascii",
      chanmodes: build_chanmodes(),
      prefix: build_prefix(),
      network: @network_name
    }
  end
end
