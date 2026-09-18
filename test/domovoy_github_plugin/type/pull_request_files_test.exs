defmodule DomovoyGithubPlugin.Type.PullRequestFilesTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.PullRequestFiles, as: PullRequestFilesType

  doctest PullRequestFilesType

  @changed_file %{path: "lib/a.ex", status: "modified", additions: 3, deletions: 1, changes: 4}

  describe "cast/2" do
    test "wraps a list of files and an empty list" do
      assert {:ok, [@changed_file]} = PullRequestFilesType.cast([@changed_file], %{})
      assert {:ok, []} = PullRequestFilesType.cast([], %{})
    end

    test "rejects a file with a wrong field and a non-list" do
      assert :error = PullRequestFilesType.cast([%{@changed_file | additions: "3"}], %{})
      assert :error = PullRequestFilesType.cast(@changed_file, %{})
    end
  end

  describe "load/1" do
    test "rejects a document with a malformed file" do
      assert :error = PullRequestFilesType.load([%{"path" => 1}])
      assert :error = PullRequestFilesType.load(%{})
    end
  end
end
