defmodule DomovoyGithubPlugin.Type.CommentsTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Comments, as: CommentsType

  doctest CommentsType

  describe "cast/2" do
    test "wraps comments with and without an author" do
      comments = [
        %{id: 1, author: "octocat", body: "a", url: "u"},
        %{id: 2, author: nil, body: "b", url: nil}
      ]

      assert {:ok, ^comments} = CommentsType.cast(comments, %{})
      assert {:ok, []} = CommentsType.cast([], %{})
    end

    test "rejects a comment without a body and a non-list" do
      assert :error = CommentsType.cast([%{id: 1, author: nil, body: nil, url: nil}], %{})
      assert :error = CommentsType.cast(%{}, %{})
    end
  end

  describe "load/1" do
    test "rejects a malformed document" do
      assert :error = CommentsType.load([%{"id" => "x"}])
    end
  end
end
