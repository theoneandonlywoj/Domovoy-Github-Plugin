defmodule DomovoyGithubPlugin.Runner.MarkPrReadyForReviewTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.MarkPrReadyForReview
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.PullRequestChange, as: PullRequestChangeType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "sends the mutation with the node id of the pull request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, [Github.pull(%{"draft" => true})])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/graphql"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = JSON.decode!(body)
        assert payload["query"] =~ "markPullRequestReadyForReview"
        assert payload["variables"] == %{"id" => "PR_node7"}

        Req.Test.json(conn, %{
          "data" => %{
            "markPullRequestReadyForReview" => %{
              "pullRequest" => %{
                "number" => 7,
                "isDraft" => false,
                "url" => "https://github.com/owner/repo/pull/7"
              }
            }
          }
        })
      end)

      assert %Value{value: change, type: PullRequestChangeType} =
               NodeRunner.run(build_node(repository), [])

      assert change == %{
               action: "ready_for_review",
               number: 7,
               url: "https://github.com/owner/repo/pull/7"
             }
    end

    test "reports a mutation GitHub rejected", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{
          "data" => nil,
          "errors" => [%{"message" => "Could not resolve to a node with the global id"}]
        })
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_graphql_failed
      assert error.reason =~ "Could not resolve"
    end

    test "reports a rejected request with its status, not as a GraphQL failure", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "Forbidden"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.reason == "Forbidden"
      assert error.metadata[:status] == 403
    end

    test "reports a pull request without a node id", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, [Map.delete(Github.pull(), "node_id")])
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.reason =~ "no node_id"
    end
  end

  @spec build_node(repository :: map()) :: Node.t()
  defp build_node(repository) do
    Node.new(%{
      name: "ready_for_review",
      runner: MarkPrReadyForReview,
      type: PullRequestChangeType,
      args: %{working_directory: {repository.root, DirectoryType}}
    })
  end
end
