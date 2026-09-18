defmodule DomovoyGithubPlugin.Type.ReviewCommentTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.ReviewComment, as: ReviewCommentType

  doctest ReviewCommentType

  describe "cast/2" do
    test "wraps a comment with and without a line" do
      assert {:ok, _} = ReviewCommentType.cast(%{id: 9, url: "u", path: "a", line: 1}, %{})
      assert {:ok, _} = ReviewCommentType.cast(%{id: 9, url: nil, path: nil, line: nil}, %{})
    end

    test "rejects a non-integer id and a missing key" do
      assert :error = ReviewCommentType.cast(%{id: "9", url: "u", path: "a", line: 1}, %{})
      assert :error = ReviewCommentType.cast(%{id: 9}, %{})
    end
  end
end
