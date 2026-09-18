defmodule DomovoyGithubPlugin.Type.BranchTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Branch, as: BranchType

  doctest BranchType

  describe "cast/2" do
    test "wraps a branch and rejects a wrong field" do
      assert {:ok, _} = BranchType.cast(%{name: "main", sha: "abc", protected: false}, %{})
      assert :error = BranchType.cast(%{name: "main", sha: nil, protected: false}, %{})
      assert :error = BranchType.cast(%{name: "main"}, %{})
    end
  end
end
