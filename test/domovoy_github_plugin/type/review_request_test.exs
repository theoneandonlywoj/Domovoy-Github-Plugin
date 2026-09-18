defmodule DomovoyGithubPlugin.Type.ReviewRequestTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.ReviewRequest, as: ReviewRequestType

  doctest ReviewRequestType

  describe "cast/2" do
    test "wraps a request with people and teams" do
      state = %{number: 7, reviewers: ["octocat"], team_reviewers: ["core"], url: "u"}

      assert {:ok, ^state} = ReviewRequestType.cast(state, %{})
    end

    test "rejects a non-string reviewer and a missing key" do
      assert :error =
               ReviewRequestType.cast(
                 %{number: 7, reviewers: [1], team_reviewers: [], url: "u"},
                 %{}
               )

      assert :error = ReviewRequestType.cast(%{number: 7, reviewers: []}, %{})
    end
  end
end
