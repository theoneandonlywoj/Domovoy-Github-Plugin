defmodule DomovoyGithubPlugin.Runner.ReviewPrTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.ReviewPr
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType
  alias DomovoyGithubPlugin.Type.PullRequestReview, as: PullRequestReviewType

  doctest ReviewPr, only: [events: 0, review: 1]

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "approves the pull request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/pulls/7/reviews"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"event" => "APPROVE", "body" => ""}

        Req.Test.json(conn, %{
          "id" => 500,
          "state" => "APPROVED",
          "user" => %{"login" => "octocat"},
          "body" => "",
          "html_url" => "u"
        })
      end)

      assert %Value{value: review, type: PullRequestReviewType} =
               NodeRunner.run(build_node(repository, %{event: {"approve", StringType}}), [])

      assert review == %{id: 500, state: :approved, author: "octocat", body: "", url: "u"}
    end

    test "requests changes with a body", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"event" => "REQUEST_CHANGES", "body" => "Please fix."}

        Req.Test.json(conn, %{
          "id" => 501,
          "state" => "CHANGES_REQUESTED",
          "body" => "Please fix."
        })
      end)

      node =
        build_node(repository, %{
          event: {"request_changes", StringType},
          body: {"Please fix.", CommentBodyType}
        })

      assert %Value{value: %{state: :changes_requested, author: nil}} = NodeRunner.run(node, [])
    end

    test "refuses an event GitHub does not accept, without calling GitHub", %{
      repository: repository
    } do
      node = build_node(repository, %{event: {"merge", StringType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_invalid_review_event
      assert error.metadata[:event] == "merge"
      assert error.metadata[:allowed_events] == ["approve", "request_changes", "comment"]
    end

    test "reports a review GitHub rejected", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{"message" => "Can not approve your own pull request"})
      end)

      assert %Error{} =
               error =
               NodeRunner.run(build_node(repository, %{event: {"approve", StringType}}), [])

      assert error.type == :github_request_failed
      assert error.reason == "Can not approve your own pull request"
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides) do
    Node.new(%{
      name: "review_pr",
      runner: ReviewPr,
      type: PullRequestReviewType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
