defmodule DomovoyGithubPlugin.Runner.GetWorkflowRunLogsTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.GetWorkflowRunLogs
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.WorkflowLogs, as: WorkflowLogsType

  doctest GetWorkflowRunLogs, only: [destination: 3]

  @zip <<80, 75, 3, 4, 20, 0, 0, 0>>

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "writes the archive under .domovoy/artifacts by default", %{repository: repository} do
      stub_download()

      node = build_node(repository, %{})

      assert %Value{value: logs, type: WorkflowLogsType} = NodeRunner.run(node, [])

      assert logs.run_id == 123
      assert logs.bytes == byte_size(@zip)

      assert logs.path ==
               Path.join([repository.root, ".domovoy", "artifacts", "workflow-run-123.zip"])

      assert File.read!(logs.path) == @zip
    end

    test "writes the archive to a named destination", %{repository: repository} do
      stub_download()

      node = build_node(repository, %{destination: {"logs/ci.zip", StringType}})

      assert %Value{value: %{path: path}} = NodeRunner.run(node, [])
      assert path == Path.join(repository.root, "logs/ci.zip")
      assert File.read!(path) == @zip
    end

    test "reports a destination it cannot write", %{repository: repository} do
      stub_download()

      blocker = Path.join(repository.root, "blocker")
      File.write!(blocker, "not a directory")

      node = build_node(repository, %{destination: {"blocker/ci.zip", StringType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_workflow_logs_write_failed
      assert error.metadata[:path] == Path.join(blocker, "ci.zip")
      assert is_atom(error.reason)
    end

    test "reports logs GitHub does not have", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository, %{}), [])
      assert error.type == :github_request_failed
      assert error.metadata[:status] == 404
    end
  end

  @spec stub_download() :: :ok
  defp stub_download do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/repos/owner/repo/actions/runs/123/logs"

      conn
      |> Plug.Conn.put_resp_header("location", "https://objects.example.com/logs.zip")
      |> Plug.Conn.send_resp(302, "")
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.host == "objects.example.com"

      conn
      |> Plug.Conn.put_resp_content_type("application/zip")
      |> Plug.Conn.send_resp(200, @zip)
    end)

    :ok
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides) do
    Node.new(%{
      name: "get_logs",
      runner: GetWorkflowRunLogs,
      type: WorkflowLogsType,
      args:
        Map.merge(
          %{working_directory: {repository.root, DirectoryType}, run_id: {123, IntegerType}},
          overrides
        )
    })
  end
end
