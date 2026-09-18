defmodule DomovoyGithubPlugin.Type.NamesTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Names, as: NamesType

  doctest NamesType

  describe "cast/2" do
    test "wraps a list of names and an empty list" do
      assert {:ok, ["octocat", "hubot"]} = NamesType.cast(["octocat", "hubot"], %{})
      assert {:ok, []} = NamesType.cast([], %{})
    end

    test "rejects a blank name, a non-string name, and a non-list" do
      assert :error = NamesType.cast(["octocat", ""], %{})
      assert :error = NamesType.cast([:octocat], %{})
      assert :error = NamesType.cast("octocat", %{})
      assert :error = NamesType.cast(nil, %{})
    end
  end

  describe "dump/1 and load/1" do
    test "round-trip the list" do
      assert {:ok, document} = NamesType.dump(["octocat"])
      assert NamesType.load(document) == {:ok, ["octocat"]}
    end
  end
end
