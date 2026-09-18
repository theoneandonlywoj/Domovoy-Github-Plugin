defmodule DomovoyGithubPlugin.Runner.GetWorkflowJobsTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.GetWorkflowJobs
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.WorkflowJobs, as: WorkflowJobsType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "lists the jobs with their steps", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/actions/runs/123/jobs"

        Req.Test.json(conn, %{
          "total_count" => 1,
          "jobs" => [
            %{
              "id" => 1,
              "name" => "test",
              "status" => "completed",
              "conclusion" => "failure",
              "html_url" => "u",
              "steps" => [
                %{
                  "number" => 1,
                  "name" => "checkout",
                  "status" => "completed",
                  "conclusion" => "success"
                },
                %{
                  "number" => 2,
                  "name" => "mix test",
                  "status" => "completed",
                  "conclusion" => "failure"
                }
              ]
            }
          ]
        })
      end)

      node =
        Node.new(%{
          name: "get_jobs",
          runner: GetWorkflowJobs,
          type: WorkflowJobsType,
          args: %{working_directory: {repository.root, DirectoryType}, run_id: {123, IntegerType}}
        })

      assert %Value{value: [job], type: WorkflowJobsType} = NodeRunner.run(node, [])
      assert job.name == "test"
      assert job.conclusion == "failure"
      assert Enum.map(job.steps, & &1.name) == ["checkout", "mix test"]
    end
  end
end
