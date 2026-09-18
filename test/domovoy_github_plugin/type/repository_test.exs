defmodule DomovoyGithubPlugin.Type.RepositoryTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Repository, as: RepositoryType

  doctest RepositoryType

  describe "cast/2" do
    test "wraps a repository and rejects a wrong field" do
      repository = %{full_name: "o/r", default_branch: "main", private: false, url: nil}

      assert {:ok, ^repository} = RepositoryType.cast(repository, %{})
      assert :error = RepositoryType.cast(%{repository | private: "no"}, %{})
      assert :error = RepositoryType.cast(%{full_name: "o/r"}, %{})
    end
  end
end
