defmodule DomovoyGithubPlugin.Type.StackTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Stack, as: StackType

  doctest StackType

  @entry %{number: 1, head: "feat-a", base: "main", url: "u"}

  describe "cast/2" do
    test "wraps a stack with one and with many pull requests" do
      one = %{base: "main", current: 1, pulls: [@entry]}
      many = %{one | pulls: [@entry, %{@entry | number: 2, head: "feat-b", base: "feat-a"}]}

      assert {:ok, ^one} = StackType.cast(one, %{})
      assert {:ok, ^many} = StackType.cast(many, %{})
    end

    test "rejects an entry with a wrong field and a stack without pulls" do
      assert :error =
               StackType.cast(%{base: "main", current: 1, pulls: [%{@entry | head: 1}]}, %{})

      assert :error = StackType.cast(%{base: "main", current: 1}, %{})
    end
  end

  describe "load/1" do
    test "rejects a document whose pulls are malformed" do
      assert :error = StackType.load(%{"base" => "main", "current" => 1, "pulls" => [%{}]})
      assert :error = StackType.load(%{"base" => "main", "current" => 1, "pulls" => "x"})
    end
  end
end
