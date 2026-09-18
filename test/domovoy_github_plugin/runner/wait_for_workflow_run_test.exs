defmodule DomovoyGithubPlugin.Runner.WaitForWorkflowRunTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.WaitForWorkflowRun
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.WorkflowRun, as: WorkflowRunType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "reads the run until it completes", %{repository: repository} do
      stub_run("queued", nil)
      stub_run("in_progress", nil)
      stub_run("completed", "success")

      node = build_node(repository, %{interval_ms: {0, IntegerType}})

      assert %Value{value: run, type: WorkflowRunType} = NodeRunner.run(node, [])
      assert run.status == :completed
      assert run.conclusion == :success
      assert run.id == 123
    end

    test "gives a run that failed as a value, not an error", %{repository: repository} do
      stub_run("completed", "failure")

      node = build_node(repository, %{interval_ms: {0, IntegerType}})

      assert %Value{value: %{status: :completed, conclusion: :failure}} = NodeRunner.run(node, [])
    end

    test "times out when the run is still going after the timeout", %{repository: repository} do
      stub_run("in_progress", nil)

      node =
        build_node(repository, %{interval_ms: {0, IntegerType}, timeout_ms: {0, IntegerType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_workflow_run_timed_out
      assert error.metadata[:run_id] == 123
      assert error.metadata[:timeout_ms] == 0
    end

    test "reports a run GitHub does not know", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository, %{}), [])
      assert error.type == :github_request_failed
      assert error.metadata[:status] == 404
    end
  end

  @spec stub_run(String.t(), String.t() | nil) :: :ok
  defp stub_run(status, conclusion) do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/repos/owner/repo/actions/runs/123"

      Req.Test.json(conn, %{
        "id" => 123,
        "name" => "CI",
        "status" => status,
        "conclusion" => conclusion,
        "html_url" => "u",
        "head_sha" => "abc"
      })
    end)

    :ok
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides) do
    Node.new(%{
      name: "wait_for_run",
      runner: WaitForWorkflowRun,
      type: WorkflowRunType,
      args:
        Map.merge(
          %{working_directory: {repository.root, DirectoryType}, run_id: {123, IntegerType}},
          overrides
        )
    })
  end
end
