defmodule DomovoyGithubPlugin.Type.PullRequestReviewsTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.PullRequestReviews, as: PullRequestReviewsType

  doctest PullRequestReviewsType

  @review %{id: 5, state: :approved, author: "octocat", body: "", url: "u"}

  describe "cast/2" do
    test "wraps a list of reviews and rejects a malformed one" do
      assert {:ok, [@review]} = PullRequestReviewsType.cast([@review], %{})
      assert :error = PullRequestReviewsType.cast([%{@review | state: :merged}], %{})
      assert :error = PullRequestReviewsType.cast(@review, %{})
    end
  end
end
