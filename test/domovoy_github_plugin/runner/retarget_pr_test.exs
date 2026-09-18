defmodule DomovoyGithubPlugin.Runner.RetargetPrTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.RetargetPr
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.PullRequestChange, as: PullRequestChangeType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "moves the base to the default branch of the repository", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, [Github.pull(%{"base" => %{"ref" => "feat-a"}})])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo"
        Req.Test.json(conn, %{"default_branch" => "develop"})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/repos/owner/repo/pulls/7"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"base" => "develop"}

        Req.Test.json(conn, Github.pull())
      end)

      assert %Value{value: change, type: PullRequestChangeType} =
               NodeRunner.run(build_node(repository), [])

      assert change.action == "retargeted"
      assert change.number == 7
    end

    test "moves the base to a named branch without reading the repository", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"base" => "release"}
        Req.Test.json(conn, Github.pull())
      end)

      node = build_node(repository, %{base_branch: {"release", StringType}})
      assert %Value{value: %{action: "retargeted"}} = NodeRunner.run(node, [])
    end

    test "reports a base GitHub refuses", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"message" => "Validation Failed"})
      end)

      node = build_node(repository, %{base_branch: {"missing", StringType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_request_failed
      assert error.metadata[:field_name] == :base_branch
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "retarget_pr",
      runner: RetargetPr,
      type: PullRequestChangeType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
