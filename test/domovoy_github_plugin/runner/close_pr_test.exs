defmodule DomovoyGithubPlugin.Runner.ClosePrTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.ClosePr
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.PullRequestChange, as: PullRequestChangeType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "closes the open pull request of the current branch", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/repos/owner/repo/pulls/7"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"state" => "closed"}

        Req.Test.json(conn, Github.pull(%{"state" => "closed"}))
      end)

      assert %Value{value: change, type: PullRequestChangeType} =
               NodeRunner.run(build_node(repository), [])

      assert change == %{action: "closed", number: 7, url: "https://github.com/owner/repo/pull/7"}
    end

    test "closes a numbered pull request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/9"
        Req.Test.json(conn, Github.pull(%{"number" => 9}))
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/9"
        Req.Test.json(conn, Github.pull(%{"number" => 9, "state" => "closed"}))
      end)

      node = build_node(repository, %{number: {9, IntegerType}})
      assert %Value{value: %{action: "closed", number: 9}} = NodeRunner.run(node, [])
    end

    test "reports a branch without an open pull request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, []) end)

      assert %Error{type: :github_pull_request_not_found} =
               NodeRunner.run(build_node(repository), [])
    end

    test "reports a rejected request with its status", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"message" => "Validation Failed"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.metadata[:status] == 422
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "close_pr",
      runner: ClosePr,
      type: PullRequestChangeType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
