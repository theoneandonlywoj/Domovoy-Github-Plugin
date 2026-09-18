defmodule DomovoyGithubPlugin.Type.PullRequestCommitsTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.PullRequestCommits, as: PullRequestCommitsType

  doctest PullRequestCommitsType

  describe "cast/2" do
    test "wraps commits with and without an author" do
      commits = [
        %{sha: "aaa", message: "feat", author: "octocat"},
        %{sha: "bbb", message: "fix", author: nil}
      ]

      assert {:ok, ^commits} = PullRequestCommitsType.cast(commits, %{})
    end

    test "rejects a commit without a sha and a non-list" do
      assert :error = PullRequestCommitsType.cast([%{message: "m", author: nil}], %{})
      assert :error = PullRequestCommitsType.cast(nil, %{})
    end
  end
end
