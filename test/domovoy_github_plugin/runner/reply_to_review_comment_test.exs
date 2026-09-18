defmodule DomovoyGithubPlugin.Runner.ReplyToReviewCommentTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.ReplyToReviewComment
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType
  alias DomovoyGithubPlugin.Type.ReviewComment, as: ReviewCommentType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "replies in the thread of the comment, quoting the remark", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/pulls/7/comments/900/replies"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"body" => "> Rename this.\n\nDone in abc123."}

        Req.Test.json(conn, %{"id" => 901, "html_url" => "u", "path" => "lib/a.ex", "line" => 12})
      end)

      blocks = [%{type: "quote", text: "Rename this."}, "Done in abc123."]
      node = build_node(repository, %{body: {blocks, CommentBodyType}})

      assert %Value{value: reply, type: ReviewCommentType} = NodeRunner.run(node, [])
      assert reply == %{id: 901, url: "u", path: "lib/a.ex", line: 12}
    end

    test "reports a comment GitHub does not know", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.metadata[:status] == 404
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "reply",
      runner: ReplyToReviewComment,
      type: ReviewCommentType,
      args:
        Map.merge(
          %{
            working_directory: {repository.root, DirectoryType},
            comment_id: {900, IntegerType},
            body: {"Done.", CommentBodyType}
          },
          overrides
        )
    })
  end
end
