defmodule DomovoyGithubPlugin.Runner.ListReviewThreadsTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.ListReviewThreads
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.ReviewThreads, as: ReviewThreadsType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "lists the threads with their first comment", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/graphql"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = JSON.decode!(body)
        assert payload["query"] =~ "reviewThreads"
        assert payload["variables"] == %{"owner" => "owner", "repo" => "repo", "number" => 7}

        Req.Test.json(conn, %{
          "data" => %{
            "repository" => %{
              "pullRequest" => %{
                "reviewThreads" => %{
                  "nodes" => [
                    %{
                      "id" => "PRRT_1",
                      "isResolved" => false,
                      "isOutdated" => true,
                      "path" => "lib/a.ex",
                      "line" => 3,
                      "comments" => %{
                        "nodes" => [
                          %{
                            "databaseId" => 900,
                            "body" => "rename",
                            "author" => %{"login" => "octocat"}
                          }
                        ]
                      }
                    },
                    %{
                      "id" => "PRRT_2",
                      "isResolved" => true,
                      "isOutdated" => false,
                      "path" => nil,
                      "line" => nil,
                      "comments" => %{"nodes" => []}
                    }
                  ]
                }
              }
            }
          }
        })
      end)

      assert %Value{value: threads, type: ReviewThreadsType} =
               NodeRunner.run(build_node(repository), [])

      assert threads == [
               %{
                 id: "PRRT_1",
                 resolved: false,
                 outdated: true,
                 path: "lib/a.ex",
                 line: 3,
                 body: "rename",
                 author: "octocat",
                 comment_id: 900
               },
               %{
                 id: "PRRT_2",
                 resolved: true,
                 outdated: false,
                 path: nil,
                 line: nil,
                 body: "",
                 author: nil,
                 comment_id: nil
               }
             ]
    end

    test "reports a query GitHub rejected", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"errors" => [%{"message" => "Something went wrong"}]})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_graphql_failed
      assert error.reason == "Something went wrong"
    end

    test "reports a rejected request with its status, not as a GraphQL failure", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "Bad credentials"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.reason == "Bad credentials"
      assert error.metadata[:status] == 401
    end
  end

  @spec build_node(repository :: map()) :: Node.t()
  defp build_node(repository) do
    Node.new(%{
      name: "list_threads",
      runner: ListReviewThreads,
      type: ReviewThreadsType,
      args: %{working_directory: {repository.root, DirectoryType}}
    })
  end
end
