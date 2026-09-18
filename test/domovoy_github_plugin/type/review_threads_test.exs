defmodule DomovoyGithubPlugin.Type.ReviewThreadsTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.ReviewThreads, as: ReviewThreadsType

  doctest ReviewThreadsType

  @thread %{
    id: "PRRT_1",
    resolved: false,
    outdated: false,
    path: "lib/a.ex",
    line: 3,
    body: "rename",
    author: "octocat",
    comment_id: 900
  }

  describe "cast/2" do
    test "wraps threads, with nil location and commenter fields" do
      bare = %{@thread | path: nil, line: nil, author: nil, comment_id: nil}

      assert {:ok, [@thread, ^bare]} = ReviewThreadsType.cast([@thread, bare], %{})
    end

    test "rejects a non-boolean resolved flag, a non-string body, and a non-list" do
      assert :error = ReviewThreadsType.cast([%{@thread | resolved: "no"}], %{})
      assert :error = ReviewThreadsType.cast([%{@thread | body: nil}], %{})
      assert :error = ReviewThreadsType.cast([%{@thread | line: "3"}], %{})
      assert :error = ReviewThreadsType.cast(@thread, %{})
    end
  end
end
