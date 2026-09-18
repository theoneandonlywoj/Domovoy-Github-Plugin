defmodule DomovoyGithubPlugin.Runner.GetWorkflowRunTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.GetWorkflowRun
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.WorkflowRun, as: WorkflowRunType

  doctest GetWorkflowRun, only: [workflow_run: 1]

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "reads the newest run of the current branch across every workflow", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/actions/runs"

        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["branch"] == "main"
        assert conn.query_params["per_page"] == "1"

        Req.Test.json(conn, %{
          "total_count" => 1,
          "workflow_runs" => [
            %{
              "id" => 123,
              "name" => "CI",
              "status" => "in_progress",
              "conclusion" => nil,
              "html_url" => "u",
              "head_sha" => "abc"
            }
          ]
        })
      end)

      assert %Value{value: run, type: WorkflowRunType} =
               NodeRunner.run(build_node(repository), [])

      assert run == %{
               id: 123,
               name: "CI",
               status: :in_progress,
               conclusion: nil,
               url: "u",
               head_sha: "abc"
             }
    end

    test "narrows to a workflow and a branch", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/actions/workflows/ci.yml/runs"

        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["branch"] == "release"

        Req.Test.json(conn, %{
          "workflow_runs" => [%{"id" => 5, "status" => "completed", "conclusion" => "failure"}]
        })
      end)

      node =
        build_node(repository, %{
          workflow: {"ci.yml", StringType},
          branch: {"release", StringType}
        })

      assert %Value{value: %{id: 5, status: :completed, conclusion: :failure}} =
               NodeRunner.run(node, [])
    end

    test "reports a branch without a run", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, %{"workflow_runs" => []}) end)

      node = build_node(repository, %{workflow: {"ci.yml", StringType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_workflow_run_not_found
      assert error.metadata[:branch] == "main"
      assert error.metadata[:workflow] == "ci.yml"
    end

    test "reports a rejected request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      assert %Error{type: :github_request_failed} = NodeRunner.run(build_node(repository), [])
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "get_run",
      runner: GetWorkflowRun,
      type: WorkflowRunType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
