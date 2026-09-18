defmodule DomovoyGithubPlugin.Runner.DispatchWorkflowTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Map, as: MapType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.DispatchWorkflow
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.WorkflowDispatch, as: WorkflowDispatchType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "starts the workflow on the current branch with inputs", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/actions/workflows/deploy.yml/dispatches"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"ref" => "main", "inputs" => %{"environment" => "staging"}}

        Plug.Conn.send_resp(conn, 204, "")
      end)

      node =
        build_node(repository, %{
          workflow: {"deploy.yml", StringType},
          inputs: {%{"environment" => "staging"}, MapType}
        })

      assert %Value{value: dispatch, type: WorkflowDispatchType} = NodeRunner.run(node, [])
      assert dispatch == %{workflow: "deploy.yml", ref: "main", dispatched: true}
    end

    test "starts the workflow on a named ref without inputs", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"ref" => "v1.2.0", "inputs" => %{}}
        Plug.Conn.send_resp(conn, 204, "")
      end)

      node =
        build_node(repository, %{workflow: {"ci.yml", StringType}, ref: {"v1.2.0", StringType}})

      assert %Value{value: %{ref: "v1.2.0"}} = NodeRunner.run(node, [])
    end

    test "reports a workflow without a dispatch trigger", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{"message" => "Workflow does not have 'workflow_dispatch' trigger"})
      end)

      node = build_node(repository, %{workflow: {"ci.yml", StringType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_request_failed
      assert error.reason =~ "workflow_dispatch"
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides) do
    Node.new(%{
      name: "dispatch",
      runner: DispatchWorkflow,
      type: WorkflowDispatchType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
