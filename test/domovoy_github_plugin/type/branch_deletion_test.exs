defmodule DomovoyGithubPlugin.Type.BranchDeletionTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.BranchDeletion, as: BranchDeletionType

  doctest BranchDeletionType

  describe "cast/2" do
    test "wraps a deletion and rejects one that did not happen" do
      assert {:ok, _} = BranchDeletionType.cast(%{branch: "feat", deleted: true}, %{})
      assert :error = BranchDeletionType.cast(%{branch: "feat", deleted: false}, %{})
      assert :error = BranchDeletionType.cast(%{branch: nil, deleted: true}, %{})
    end
  end
end
