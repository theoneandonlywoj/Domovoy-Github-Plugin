defmodule DomovoyGithubPlugin.Runner.AssignPrTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.AssignPr
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.Assignees, as: AssigneesType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "posts the assignees and lists every assignee after the change", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/issues/7/assignees"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"assignees" => ["hubot"]}

        Req.Test.json(
          conn,
          Github.pull(%{"assignees" => [%{"login" => "octocat"}, %{"login" => "hubot"}]})
        )
      end)

      node = build_node(repository, ["hubot"])

      assert %Value{value: ["octocat", "hubot"], type: AssigneesType} = NodeRunner.run(node, [])
    end

    test "reports a rejected request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "Forbidden"})
      end)

      assert %Error{type: :github_request_failed} =
               NodeRunner.run(build_node(repository, ["x"]), [])
    end
  end

  @spec build_node(map(), [String.t()]) :: Node.t()
  defp build_node(repository, assignees) do
    Node.new(%{
      name: "assign_pr",
      runner: AssignPr,
      type: AssigneesType,
      args: %{
        working_directory: {repository.root, DirectoryType},
        assignees: {assignees, AssigneesType}
      }
    })
  end
end
