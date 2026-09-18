defmodule DomovoyGithubPlugin.Type.IssueTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Issue, as: IssueType

  require IssueType

  doctest IssueType

  @issue %{number: 9, title: "Bug", body: "", state: :open, labels: [], assignees: [], url: nil}

  describe "cast/2" do
    test "wraps an open and a closed issue" do
      assert {:ok, @issue} = IssueType.cast(@issue, %{})
      assert {:ok, _} = IssueType.cast(%{@issue | state: :closed}, %{})
    end

    test "rejects a text state, a non-string label, and a missing key" do
      assert :error = IssueType.cast(%{@issue | state: "open"}, %{})
      assert :error = IssueType.cast(%{@issue | labels: [1]}, %{})
      assert :error = IssueType.cast(Map.delete(@issue, :labels), %{})
      assert :error = IssueType.cast(%{number: 9}, %{})
    end
  end

  describe "load/1" do
    test "rejects a state this type does not give" do
      {:ok, document} = IssueType.dump(@issue)
      assert :error = IssueType.load(%{document | "state" => "merged"})
      assert :error = IssueType.load(%{})
    end
  end
end
