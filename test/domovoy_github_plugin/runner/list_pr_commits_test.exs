defmodule DomovoyGithubPlugin.Runner.ListPrCommitsTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.ListPrCommits
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.PullRequestCommits, as: PullRequestCommitsType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "lists the commits with the login, or the name when GitHub knows no login", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/7/commits"

        Req.Test.json(conn, [
          %{
            "sha" => "aaa",
            "author" => %{"login" => "octocat"},
            "commit" => %{"message" => "feat: a", "author" => %{"name" => "Octo Cat"}}
          },
          %{
            "sha" => "bbb",
            "author" => nil,
            "commit" => %{"message" => "fix: b", "author" => %{"name" => "Some One"}}
          }
        ])
      end)

      assert %Value{value: commits, type: PullRequestCommitsType} =
               NodeRunner.run(build_node(repository), [])

      assert commits == [
               %{sha: "aaa", message: "feat: a", author: "octocat"},
               %{sha: "bbb", message: "fix: b", author: "Some One"}
             ]
    end
  end

  @spec build_node(repository :: map()) :: Node.t()
  defp build_node(repository) do
    Node.new(%{
      name: "list_pr_commits",
      runner: ListPrCommits,
      type: PullRequestCommitsType,
      args: %{working_directory: {repository.root, DirectoryType}}
    })
  end
end
