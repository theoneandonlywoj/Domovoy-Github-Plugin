defmodule DomovoyGithubPlugin.Type.PullRequestMergeTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.PullRequestMerge, as: PullRequestMergeType

  doctest PullRequestMergeType

  describe "cast/2" do
    test "wraps a merge with and without a sha" do
      merged = %{merged: true, sha: "6dcb09b", message: "merged"}
      refused = %{merged: false, sha: nil, message: "not mergeable"}

      assert {:ok, ^merged} = PullRequestMergeType.cast(merged, %{})
      assert {:ok, ^refused} = PullRequestMergeType.cast(refused, %{})
    end

    test "rejects a non-boolean merged flag, a non-string message, and a missing key" do
      assert :error = PullRequestMergeType.cast(%{merged: "yes", sha: nil, message: "m"}, %{})
      assert :error = PullRequestMergeType.cast(%{merged: true, sha: nil, message: nil}, %{})
      assert :error = PullRequestMergeType.cast(%{merged: true}, %{})
    end
  end
end
