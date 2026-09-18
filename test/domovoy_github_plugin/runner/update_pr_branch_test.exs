defmodule DomovoyGithubPlugin.Runner.UpdatePrBranchTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.UpdatePrBranch
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.PullRequestChange, as: PullRequestChangeType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "starts the update and reports the pull request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/repos/owner/repo/pulls/7/update-branch"

        conn
        |> Plug.Conn.put_status(202)
        |> Req.Test.json(%{"message" => "Updating pull request branch.", "url" => "u"})
      end)

      assert %Value{value: change, type: PullRequestChangeType} =
               NodeRunner.run(build_node(repository), [])

      assert change == %{
               action: "branch_updated",
               number: 7,
               url: "https://github.com/owner/repo/pull/7"
             }
    end

    test "reports a branch GitHub cannot update", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{"message" => "merge conflict between base and head"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.reason == "merge conflict between base and head"
    end
  end

  @spec build_node(repository :: map()) :: Node.t()
  defp build_node(repository) do
    Node.new(%{
      name: "update_pr_branch",
      runner: UpdatePrBranch,
      type: PullRequestChangeType,
      args: %{working_directory: {repository.root, DirectoryType}}
    })
  end
end
