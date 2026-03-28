defmodule IRCane.Protocol.ModeTest do
  use ExUnit.Case

  alias IRCane.Protocol.Mode

  describe "parse_modes/2" do
    test "handles applying param_always mode with no param" do
      modes = %{?T => {:param_always, :test, []}}

      assert [{:invalid, {:no_param, :test}}] = Mode.parse_modes(["+T"], modes)
    end

    test "handles applying list mode with no param" do
      modes = %{?T => {:param_always, :test, list: true}}

      assert [{:list, :test}] = Mode.parse_modes(["+T"], modes)
    end

    test "handles applying param_always mode with a param" do
      modes = %{?T => {:param_always, :test, []}}

      assert [{:add, {:test, "param"}}] = Mode.parse_modes(["+T", "param"], modes)
    end

    test "handles removing param_always mode with no param" do
      modes = %{?T => {:param_always, :test, []}}

      assert [{:invalid, {:no_param, :test}}] = Mode.parse_modes(["-T"], modes)
    end

    test "handles removing param_always mode with a param" do
      modes = %{?T => {:param_always, :test, []}}

      assert [{:remove, {:test, "param"}}] = Mode.parse_modes(["-T", "param"], modes)
    end

    test "handles applying param_when_set mode with no param" do
      modes = %{?T => {:param_when_set, :test, []}}

      assert [{:invalid, {:no_param, :test}}] = Mode.parse_modes(["+T"], modes)
    end

    test "handles applying param_when_set mode with a param" do
      modes = %{?T => {:param_when_set, :test, []}}

      assert [{:add, {:test, "param"}}] = Mode.parse_modes(["+T", "param"], modes)
    end

    test "handles removing param_when_set mode with no param" do
      modes = %{?T => {:param_when_set, :test, []}}

      assert [{:remove, :test}] = Mode.parse_modes(["-T"], modes)
    end

    test "does not consume param when removing param_when_set mode" do
      modes = %{
        ?T => {:param_when_set, :test, []},
        ?U => {:param_always, :other, []}
      }

      assert [{:remove, :test}, {:remove, {:other, "param"}}] =
               Mode.parse_modes(["-TU", "param"], modes)
    end

    test "handles applying no_param mode with no param" do
      modes = %{?T => {:no_param, :test, []}}

      assert [{:add, :test}] = Mode.parse_modes(["+T"], modes)
    end

    test "does not consume param when applying no_param mode" do
      modes = %{
        ?T => {:no_param, :test, []},
        ?U => {:param_always, :other, []}
      }

      assert [{:add, :test}, {:add, {:other, "param"}}] =
               Mode.parse_modes(["+TU", "param"], modes)
    end

    test "handles removing no_param mode with no param" do
      modes = %{?T => {:no_param, :test, []}}

      assert [{:remove, :test}] = Mode.parse_modes(["-T"], modes)
    end

    test "does not consume param when removing no_param mode" do
      modes = %{
        ?T => {:no_param, :test, []},
        ?U => {:param_always, :other, []}
      }

      assert [{:remove, :test}, {:remove, {:other, "param"}}] =
               Mode.parse_modes(["-TU", "param"], modes)
    end

    test "preserves mode and param order" do
      modes = %{
        ?a => {:param_always, :mode_a, []},
        ?b => {:param_always, :mode_b, []},
        ?c => {:param_always, :mode_c, []},
        ?d => {:no_param, :mode_d, []}
      }

      assert [
               {:add, {:mode_a, "foo"}},
               {:add, {:mode_b, "bar"}},
               {:add, {:mode_c, "baz"}},
               {:add, :mode_d}
             ] = Mode.parse_modes(["+abcd", "foo", "bar", "baz"], modes)
    end

    test "handles plus and minus signs in the middle of a mode string" do
      modes = %{
        ?T => {:no_param, :test, []}
      }

      assert [
               {:add, :test},
               {:remove, :test},
               {:add, :test},
               {:remove, :test}
             ] = Mode.parse_modes(["+T-T+-+-+-+T-++-+--T"], modes)
    end

    test "defaults to applying when mode string does not start with a plus or minus" do
      modes = %{?T => {:no_param, :test, []}}

      assert [{:add, :test}, {:remove, :test}] = Mode.parse_modes(["T-T"], modes)
    end

    test "handles unknown mode letters" do
      assert [{:invalid, {:unknown_mode, ?T}}] = Mode.parse_modes(["+T"], %{})
    end
  end

  describe "parse/2" do
    test "parses mode string and applies parse functions to params" do
      parse_fn = fn str ->
        case Integer.parse(str) do
          {int, ""} -> {:ok, int}
          _ -> :error
        end
      end

      modes = %{?T => {:param_always, :test, parse: parse_fn}}

      assert [{:add, {:test, 42}}] = Mode.parse(["+T", "42"], modes)
    end

    test "returns invalid for bad param after parsing mode string" do
      parse_fn = fn _ -> :error end
      modes = %{?T => {:param_always, :test, parse: parse_fn}}

      assert [{:invalid, {:invalid_param, :test, "bad"}}] = Mode.parse(["+T", "bad"], modes)
    end

    test "passes through string params when no parse function defined" do
      modes = %{?T => {:param_always, :test, []}}

      assert [{:add, {:test, "param"}}] = Mode.parse(["+T", "param"], modes)
    end

    test "handles modes without params end-to-end" do
      modes = %{?T => {:no_param, :test, []}}

      assert [{:add, :test}, {:remove, :test}] = Mode.parse(["+T-T"], modes)
    end
  end

  describe "format_modes/2" do
    test "handles modes without a parameter" do
      modes = %{?T => {:no_param, :test, []}}

      assert ["+T"] = Mode.format_modes([{:add, :test}], modes)
    end

    test "handles modes with a parameter" do
      modes = %{?T => {:param_always, :test, []}}

      assert ["+T", "foo"] = Mode.format_modes([{:add, {:test, "foo"}}], modes)
    end

    test "preserves mode order" do
      modes = %{
        ?a => {:param_always, :mode_a, []},
        ?b => {:param_always, :mode_b, []},
        ?c => {:param_always, :mode_c, []},
        ?d => {:no_param, :mode_d, []}
      }

      assert ["+abcd", "foo", "bar", "baz"] =
               Mode.format_modes(
                 [
                   {:add, {:mode_a, "foo"}},
                   {:add, {:mode_b, "bar"}},
                   {:add, {:mode_c, "baz"}},
                   {:add, :mode_d}
                 ],
                 modes
               )
    end

    test "handles both mode addition and removal" do
      modes = %{?T => {:no_param, :test, []}}

      assert ["+T-T+T-T"] =
               Mode.format_modes(
                 [
                   {:add, :test},
                   {:remove, :test},
                   {:add, :test},
                   {:remove, :test}
                 ],
                 modes
               )
    end

    test "skips unknown modes" do
      assert [""] =
               Mode.format_modes(
                 [
                   {:add, :not_a_mode},
                   {:add, {:not_a_mode, "foo"}}
                 ],
                 %{}
               )
    end
  end

  describe "format/2" do
    test "formats non-binary params and produces mode string" do
      modes = %{?T => {:param_always, :test, format: &to_string/1}}

      assert ["+T", "42"] = Mode.format([{:add, {:test, 42}}], modes)
    end

    test "uses inspect/1 as default format function for non-binary params" do
      modes = %{?T => {:param_always, :test, []}}

      assert ["+T", ":atom"] = Mode.format([{:add, {:test, :atom}}], modes)
    end

    test "passes through binary params unchanged" do
      modes = %{?T => {:param_always, :test, []}}

      assert ["+T", "param"] = Mode.format([{:add, {:test, "param"}}], modes)
    end

    test "handles modes without params end-to-end" do
      modes = %{?T => {:no_param, :test, []}}

      assert ["+T-T"] = Mode.format([{:add, :test}, {:remove, :test}], modes)
    end
  end

  describe "parse_params/2" do
    test "passes through modes without params" do
      modes = %{?T => {:no_param, :test, []}}

      assert [{:add, :test}] = Mode.parse_params([{:add, :test}], modes)
    end

    test "passes through modes if no :parse option" do
      modes = %{?T => {:param_always, :test, []}}

      assert [{:add, {:test, "67"}}] = Mode.parse_params([{:add, {:test, "67"}}], modes)
    end

    test "parses params using :parse option" do
      parse_fn = fn str ->
        case Integer.parse(str) do
          {int, ""} -> {:ok, int}
          _ -> :error
        end
      end

      modes = %{?T => {:param_always, :test, parse: parse_fn}}

      assert [{:add, {:test, 67}}] = Mode.parse_params([{:add, {:test, "67"}}], modes)
    end

    test "replaces modes with invalid tuple if parse function fails" do
      parse_fn = fn _ -> :error end
      modes = %{?T => {:param_always, :test, parse: parse_fn}}

      assert [{:invalid, {:invalid_param, :test, "abc"}}] =
               Mode.parse_params([{:add, {:test, "abc"}}], modes)
    end
  end

  describe "format_params/2" do
    test "passes through binary params" do
      modes = %{?T => {:param_always, :test, []}}

      assert [{:add, {:test, "param"}}] = Mode.format_params([{:add, {:test, "param"}}], modes)
    end

    test "formats params using :format option" do
      modes = %{?T => {:param_always, :test, format: &to_string/1}}

      assert [{:add, {:test, "67"}}] = Mode.format_params([{:add, {:test, 67}}], modes)
    end

    test "defaults to inspect/1 if no :format option" do
      modes = %{?T => {:param_always, :test, []}}

      assert [{:add, {:test, ":atom"}}] = Mode.format_params([{:add, {:test, :atom}}], modes)
    end

    test "passes through modes without params" do
      modes = %{?T => {:no_param, :test, []}}

      assert [{:add, :test}] = Mode.format_params([{:add, :test}], modes)
    end
  end
end
