defmodule IRCane.Channel.RoleTest do
  use ExUnit.Case

  alias IRCane.Channel.Role

  describe "max/1" do
    test "returns nil for an empty list" do
      assert nil == Role.max([])
    end

    test "returns the only role for a single-item list" do
      assert :operator == Role.max([:operator])
    end

    test "returns the highest ranked role from a mixed list" do
      assert :founder == Role.max([:voice, :operator, :protect, :founder])
    end

    test "prefers known roles over unknown ones" do
      assert :voice == Role.max([:unknown_role, :voice])
    end
  end

  describe "compare/2" do
    test "returns a negative value when the first role is lower" do
      assert Role.compare(:voice, :operator) < 0
    end

    test "returns a positive value when the first role is higher" do
      assert Role.compare(:founder, :operator) > 0
    end

    test "returns zero for equal roles" do
      assert 0 == Role.compare(:operator, :operator)
    end

    test "treats unknown roles as rank 0" do
      assert 0 == Role.compare(:unknown_role, :unknown_role)
      assert Role.compare(:unknown_role, :voice) < 0
      assert Role.compare(:voice, :unknown_role) > 0
    end
  end

  describe "highest_target/1" do
    test "returns configured highest target for roles that define one" do
      assert :voice == Role.highest_target(:halfop)
      assert :operator == Role.highest_target(:protect)
      assert :protect == Role.highest_target(:founder)
    end

    test "returns the role itself when highest_target is not configured" do
      assert :voice == Role.highest_target(:voice)
      assert :operator == Role.highest_target(:operator)
    end

    test "returns unknown roles unchanged" do
      assert :unknown_role == Role.highest_target(:unknown_role)
    end
  end

  describe "prefix/1" do
    test "returns configured prefixes" do
      assert "+" == Role.prefix(:voice)
      assert "%" == Role.prefix(:halfop)
      assert "@" == Role.prefix(:operator)
      assert "&" == Role.prefix(:protect)
      assert "~" == Role.prefix(:founder)
    end

    test "returns an empty string for unknown roles" do
      assert "" == Role.prefix(:unknown_role)
    end

    test "returns an empty string for nil" do
      assert "" == Role.prefix(nil)
    end
  end
end
