defmodule DomovoyGithubPlugin.Runner.ReopenPrTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.ReopenPr
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.PullRequestChange, as: PullRequestChangeType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "reopens the newest closed pull request of the current branch", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["head"] == "owner:main"
        assert conn.query_params["state"] == "closed"

        Req.Test.json(conn, [Github.pull(%{"state" => "closed"})])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/repos/owner/repo/pulls/7"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"state" => "open"}

        Req.Test.json(conn, Github.pull())
      end)

      assert %Value{value: change, type: PullRequestChangeType} =
               NodeRunner.run(build_node(repository), [])

      assert change.action == "reopened"
      assert change.number == 7
    end

    test "skips a merged pull request and reopens the newest closed one", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, [
          Github.pull(%{
            "number" => 8,
            "state" => "closed",
            "merged_at" => "2026-09-09T18:26:21Z"
          }),
          Github.pull(%{"number" => 7, "state" => "closed"})
        ])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/7"
        Req.Test.json(conn, Github.pull())
      end)

      assert %Value{value: %{action: "reopened", number: 7}} =
               NodeRunner.run(build_node(repository), [])
    end

    test "reports a branch whose only closed pull request was merged", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, [
          Github.pull(%{"state" => "closed", "merged_at" => "2026-09-09T18:26:21Z"})
        ])
      end)

      assert %Error{type: :github_pull_request_not_found} =
               NodeRunner.run(build_node(repository), [])
    end

    test "reopens a numbered pull request without a search", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/repos/owner/repo/pulls/9"
        Req.Test.json(conn, Github.pull(%{"number" => 9}))
      end)

      node = build_node(repository, %{number: {9, IntegerType}})
      assert %Value{value: %{action: "reopened", number: 9}} = NodeRunner.run(node, [])
    end

    test "reports a branch without a closed pull request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, []) end)

      assert %Error{type: :github_pull_request_not_found} =
               NodeRunner.run(build_node(repository), [])
    end

    test "reports a number that names no pull request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      node = build_node(repository, %{number: {99, IntegerType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_pull_request_not_found
      assert error.metadata[:number] == 99
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "reopen_pr",
      runner: ReopenPr,
      type: PullRequestChangeType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
