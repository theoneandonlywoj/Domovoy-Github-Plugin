defmodule DomovoyGithubPlugin.Runner.MergePrTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.MergePr
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.PullRequestMerge, as: PullRequestMergeType

  doctest MergePr, only: [merge_methods: 0]

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "merges the open pull request of the current branch", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["head"] == "owner:main"
        Req.Test.json(conn, [Github.pull()])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/repos/owner/repo/pulls/7/merge"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"merge_method" => "merge"}

        Req.Test.json(conn, %{"sha" => "6dcb09b", "merged" => true, "message" => "merged"})
      end)

      assert %Value{value: merge, type: PullRequestMergeType} =
               NodeRunner.run(build_node(repository), [])

      assert merge == %{merged: true, sha: "6dcb09b", message: "merged"}
    end

    test "merges a numbered pull request with a method, title, and message", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/9"
        Req.Test.json(conn, Github.pull(%{"number" => 9}))
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/9/merge"

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body) == %{
                 "merge_method" => "squash",
                 "commit_title" => "feat: search (#9)",
                 "commit_message" => "why"
               }

        Req.Test.json(conn, %{"sha" => "abc", "merged" => true, "message" => "merged"})
      end)

      node =
        build_node(repository, %{
          number: {9, IntegerType},
          merge_method: {"squash", StringType},
          commit_title: {"feat: search (#9)", StringType},
          commit_message: {"why", StringType}
        })

      assert %Value{value: %{merged: true, sha: "abc"}} = NodeRunner.run(node, [])
    end

    test "refuses a merge method GitHub does not accept, without calling GitHub", %{
      repository: repository
    } do
      node = build_node(repository, %{merge_method: {"fast-forward", StringType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_invalid_merge_method
      assert error.metadata[:merge_method] == "fast-forward"
      assert error.metadata[:allowed_merge_methods] == ["merge", "squash", "rebase"]
    end

    test "reports a pull request GitHub refuses to merge", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(405)
        |> Req.Test.json(%{"message" => "Pull Request is not mergeable"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_pull_request_not_mergeable
      assert error.reason == "Pull Request is not mergeable"
      assert error.metadata[:number] == 7
    end

    test "reports a head that moved as not mergeable", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(409)
        |> Req.Test.json(%{"message" => "Head branch was modified"})
      end)

      assert %Error{type: :github_pull_request_not_mergeable} =
               NodeRunner.run(build_node(repository), [])
    end

    test "reports a branch without an open pull request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, []) end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_pull_request_not_found
      assert error.metadata[:head] == "owner:main"
    end

    test "reports another rejected request with its status", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "Forbidden"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.metadata[:status] == 403
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "merge_pr",
      runner: MergePr,
      type: PullRequestMergeType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
