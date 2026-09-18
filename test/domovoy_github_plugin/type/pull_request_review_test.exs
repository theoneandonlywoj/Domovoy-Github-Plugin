defmodule DomovoyGithubPlugin.Type.PullRequestReviewTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.PullRequestReview, as: PullRequestReviewType

  require PullRequestReviewType

  doctest PullRequestReviewType

  @review %{id: 5, state: :approved, author: "octocat", body: "", url: "u"}

  describe "states/0 and is_state/1" do
    test "name every state" do
      assert PullRequestReviewType.states() == [
               :approved,
               :changes_requested,
               :commented,
               :dismissed,
               :pending,
               :invalid_state
             ]

      assert Enum.all?(PullRequestReviewType.states(), &PullRequestReviewType.is_state/1)
      refute PullRequestReviewType.is_state("approved")
    end
  end

  describe "parse_state/1" do
    test "reads each text of GitHub" do
      assert PullRequestReviewType.parse_state("APPROVED") == :approved
      assert PullRequestReviewType.parse_state("CHANGES_REQUESTED") == :changes_requested
      assert PullRequestReviewType.parse_state("COMMENTED") == :commented
      assert PullRequestReviewType.parse_state("DISMISSED") == :dismissed
      assert PullRequestReviewType.parse_state("PENDING") == :pending
      assert PullRequestReviewType.parse_state("approved") == :invalid_state
    end
  end

  describe "cast/2 and load/1" do
    test "wrap a review and reject a text state" do
      assert {:ok, @review} = PullRequestReviewType.cast(@review, %{})
      assert :error = PullRequestReviewType.cast(%{@review | state: "APPROVED"}, %{})
      assert :error = PullRequestReviewType.cast(%{@review | id: nil}, %{})
    end

    test "load rejects a state text this type does not give" do
      {:ok, document} = PullRequestReviewType.dump(@review)
      assert :error = PullRequestReviewType.load(%{document | "state" => "merged"})
      assert :error = PullRequestReviewType.load(%{})
    end
  end
end
