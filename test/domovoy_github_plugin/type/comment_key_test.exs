defmodule DomovoyGithubPlugin.Type.CommentKeyTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.CommentKey, as: CommentKeyType

  doctest CommentKeyType

  describe "cast/2" do
    test "wraps a key of lowercase letters, digits, underscores, and dashes" do
      assert {:ok, "checks"} = CommentKeyType.cast("checks", %{})
      assert {:ok, "a1_b-2"} = CommentKeyType.cast("a1_b-2", %{})
    end

    test "rejects a key that would break the HTML marker" do
      assert :error = CommentKeyType.cast("checks -->", %{})
      assert :error = CommentKeyType.cast("two words", %{})
      assert :error = CommentKeyType.cast("Checks", %{})
      assert :error = CommentKeyType.cast("", %{})
    end

    test "rejects a non-string" do
      assert :error = CommentKeyType.cast(:checks, %{})
      assert :error = CommentKeyType.cast(nil, %{})
    end
  end

  describe "dump/1 and load/1" do
    test "round-trip the key" do
      assert {:ok, document} = CommentKeyType.dump("checks")
      assert CommentKeyType.load(document) == {:ok, "checks"}
    end
  end
end
