defmodule DomovoyGithubPlugin.Runner.ListPrCommentsTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.ListPrComments
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.Comments, as: CommentsType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "lists the conversation comments", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/issues/7/comments"

        Req.Test.json(conn, [
          %{"id" => 1, "user" => %{"login" => "octocat"}, "body" => "a", "html_url" => "u1"},
          %{"id" => 2, "user" => nil, "body" => nil, "html_url" => "u2"}
        ])
      end)

      assert %Value{value: comments, type: CommentsType} =
               NodeRunner.run(build_node(repository), [])

      assert comments == [
               %{id: 1, author: "octocat", body: "a", url: "u1"},
               %{id: 2, author: nil, body: "", url: "u2"}
             ]
    end
  end

  @spec build_node(repository :: map()) :: Node.t()
  defp build_node(repository) do
    Node.new(%{
      name: "list_pr_comments",
      runner: ListPrComments,
      type: CommentsType,
      args: %{working_directory: {repository.root, DirectoryType}}
    })
  end
end
