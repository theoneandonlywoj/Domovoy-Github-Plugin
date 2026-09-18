defmodule DomovoyGithubPlugin.Runner.ResolveReviewThreadTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.ResolveReviewThread
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.ReviewThreadChange, as: ReviewThreadChangeType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "resolves the thread without reading the pull request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/graphql"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = JSON.decode!(body)
        assert payload["query"] =~ "resolveReviewThread"
        assert payload["variables"] == %{"id" => "PRRT_1"}

        Req.Test.json(conn, %{
          "data" => %{
            "resolveReviewThread" => %{"thread" => %{"id" => "PRRT_1", "isResolved" => true}}
          }
        })
      end)

      assert %Value{value: change, type: ReviewThreadChangeType} =
               NodeRunner.run(build_node(repository), [])

      assert change == %{id: "PRRT_1", resolved: true}
    end

    test "reports a thread GitHub cannot find", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"errors" => [%{"message" => "Could not resolve to a node"}]})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_graphql_failed
      assert error.metadata[:field_name] == :thread_id
    end

    test "reports a rejected request with its status, not as a GraphQL failure", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "Bad credentials"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.reason == "Bad credentials"
      assert error.metadata[:status] == 401
      assert error.metadata[:field_name] == :thread_id
    end
  end

  @spec build_node(repository :: map()) :: Node.t()
  defp build_node(repository) do
    Node.new(%{
      name: "resolve_thread",
      runner: ResolveReviewThread,
      type: ReviewThreadChangeType,
      args: %{
        working_directory: {repository.root, DirectoryType},
        thread_id: {"PRRT_1", StringType}
      }
    })
  end
end
