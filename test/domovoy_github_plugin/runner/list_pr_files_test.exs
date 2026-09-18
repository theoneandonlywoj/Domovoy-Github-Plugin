defmodule DomovoyGithubPlugin.Runner.ListPrFilesTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.ListPrFiles
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.PullRequestFiles, as: PullRequestFilesType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "lists the files of the pull request across pages", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/7/files"

        conn
        |> Plug.Conn.put_resp_header(
          "link",
          ~s(<https://api.github.com/repos/owner/repo/pulls/7/files?page=2>; rel="next")
        )
        |> Req.Test.json([
          %{
            "filename" => "lib/a.ex",
            "status" => "modified",
            "additions" => 3,
            "deletions" => 1,
            "changes" => 4
          }
        ])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, [
          %{
            "filename" => "lib/b.ex",
            "status" => "added",
            "additions" => 10,
            "deletions" => 0,
            "changes" => 10
          }
        ])
      end)

      assert %Value{value: files, type: PullRequestFilesType} =
               NodeRunner.run(build_node(repository), [])

      assert files == [
               %{path: "lib/a.ex", status: "modified", additions: 3, deletions: 1, changes: 4},
               %{path: "lib/b.ex", status: "added", additions: 10, deletions: 0, changes: 10}
             ]
    end

    test "reports a rejected request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "Server Error"})
      end)

      assert %Error{type: :github_request_failed} = NodeRunner.run(build_node(repository), [])
    end
  end

  @spec build_node(repository :: map()) :: Node.t()
  defp build_node(repository) do
    Node.new(%{
      name: "list_pr_files",
      runner: ListPrFiles,
      type: PullRequestFilesType,
      args: %{working_directory: {repository.root, DirectoryType}}
    })
  end
end
