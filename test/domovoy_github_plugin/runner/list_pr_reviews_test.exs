defmodule DomovoyGithubPlugin.Runner.ListPrReviewsTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.ListPrReviews
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.PullRequestReviews, as: PullRequestReviewsType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "lists the reviews with their states", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/7/reviews"

        Req.Test.json(conn, [
          %{"id" => 1, "state" => "COMMENTED", "user" => %{"login" => "a"}, "body" => "hm"},
          %{"id" => 2, "state" => "APPROVED", "user" => %{"login" => "b"}, "body" => ""}
        ])
      end)

      assert %Value{value: reviews, type: PullRequestReviewsType} =
               NodeRunner.run(build_node(repository), [])

      assert Enum.map(reviews, &{&1.author, &1.state}) == [{"a", :commented}, {"b", :approved}]
    end
  end

  @spec build_node(repository :: map()) :: Node.t()
  defp build_node(repository) do
    Node.new(%{
      name: "list_pr_reviews",
      runner: ListPrReviews,
      type: PullRequestReviewsType,
      args: %{working_directory: {repository.root, DirectoryType}}
    })
  end
end
