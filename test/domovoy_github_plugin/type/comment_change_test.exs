defmodule DomovoyGithubPlugin.Type.CommentChangeTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.CommentChange, as: CommentChangeType

  doctest CommentChangeType

  describe "cast/2" do
    test "wraps a created and an updated change" do
      created = %{action: "created", id: 1, url: "u"}
      assert {:ok, ^created} = CommentChangeType.cast(created, %{})
      assert {:ok, _} = CommentChangeType.cast(%{created | action: "updated"}, %{})
    end

    test "rejects another action, a non-integer id, and a missing key" do
      assert :error = CommentChangeType.cast(%{action: "deleted", id: 1, url: "u"}, %{})
      assert :error = CommentChangeType.cast(%{action: "created", id: "1", url: "u"}, %{})
      assert :error = CommentChangeType.cast(%{action: "created"}, %{})
    end
  end
end
