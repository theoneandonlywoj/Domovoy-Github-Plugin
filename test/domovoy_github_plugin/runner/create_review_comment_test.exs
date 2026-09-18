defmodule DomovoyGithubPlugin.Runner.CreateReviewCommentTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.CreateReviewComment
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType
  alias DomovoyGithubPlugin.Type.ReviewComment, as: ReviewCommentType

  doctest CreateReviewComment, only: [comment: 2]

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "comments on a line at the head commit of the pull request", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/pulls/7/comments"

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body) == %{
                 "body" => "Rename this.",
                 "commit_id" => "abc123",
                 "path" => "lib/a.ex",
                 "line" => 12,
                 "side" => "RIGHT"
               }

        Req.Test.json(conn, %{"id" => 900, "html_url" => "u", "path" => "lib/a.ex", "line" => 12})
      end)

      assert %Value{value: comment, type: ReviewCommentType} =
               NodeRunner.run(build_node(repository), [])

      assert comment == %{id: 900, url: "u", path: "lib/a.ex", line: 12}
    end

    test "sends the left side when asked", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body)["side"] == "LEFT"
        Req.Test.json(conn, %{"id" => 900})
      end)

      node = build_node(repository, %{side: {"LEFT", StringType}})
      assert %Value{value: %{id: 900, path: nil}} = NodeRunner.run(node, [])
    end

    test "reports a pull request without a head sha", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, [Github.pull(%{"head" => %{"ref" => "main"}})])
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.reason =~ "no head sha"
    end

    test "reports a line GitHub cannot find in the diff", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{
          "message" => "Validation Failed",
          "errors" => [%{"message" => "line"}]
        })
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.reason == "Validation Failed; line"
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "review_comment",
      runner: CreateReviewComment,
      type: ReviewCommentType,
      args:
        Map.merge(
          %{
            working_directory: {repository.root, DirectoryType},
            path: {"lib/a.ex", StringType},
            line: {12, IntegerType},
            body: {"Rename this.", CommentBodyType}
          },
          overrides
        )
    })
  end
end
