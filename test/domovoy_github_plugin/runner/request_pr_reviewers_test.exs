defmodule DomovoyGithubPlugin.Runner.RequestPrReviewersTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.RequestPrReviewers
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.Names, as: NamesType
  alias DomovoyGithubPlugin.Type.ReviewRequest, as: ReviewRequestType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "asks people and teams to review, and lists every pending reviewer", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/pulls/7/requested_reviewers"

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body) == %{
                 "reviewers" => ["octocat"],
                 "team_reviewers" => ["core"]
               }

        Req.Test.json(
          conn,
          Github.pull(%{
            "requested_reviewers" => [%{"login" => "octocat"}, %{"login" => "hubot"}],
            "requested_teams" => [%{"slug" => "core"}]
          })
        )
      end)

      node =
        build_node(repository, %{
          reviewers: {["octocat"], NamesType},
          team_reviewers: {["core"], NamesType}
        })

      assert %Value{value: request, type: ReviewRequestType} = NodeRunner.run(node, [])

      assert request == %{
               number: 7,
               reviewers: ["octocat", "hubot"],
               team_reviewers: ["core"],
               url: "https://github.com/owner/repo/pull/7"
             }
    end

    test "sends empty lists when no reviewer is named", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"reviewers" => [], "team_reviewers" => []}

        Req.Test.json(conn, Github.pull())
      end)

      assert %Value{value: %{reviewers: [], team_reviewers: []}} =
               NodeRunner.run(build_node(repository), [])
    end

    test "rejects a blank login before calling GitHub", %{repository: repository} do
      node = build_node(repository, %{reviewers: {["octocat", " "], NamesType}})

      assert %Error{type: :invalid_input} = NodeRunner.run(node, [])
    end

    test "reports a reviewer GitHub does not know", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{"message" => "Reviews may only be requested from collaborators."})
      end)

      node = build_node(repository, %{reviewers: {["stranger"], NamesType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_request_failed
      assert error.metadata[:status] == 422
      assert error.metadata[:field_name] == :reviewers
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "request_reviewers",
      runner: RequestPrReviewers,
      type: ReviewRequestType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
