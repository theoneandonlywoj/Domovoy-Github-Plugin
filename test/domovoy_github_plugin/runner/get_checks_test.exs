defmodule DomovoyGithubPlugin.Runner.GetChecksTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.GetChecks
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Test.Repository
  alias DomovoyGithubPlugin.Type.Checks, as: ChecksType

  doctest GetChecks, only: [summarize: 3]

  setup :stub_requests

  setup do
    repository = Github.repository!()
    sha = Repository.git!(["-C", repository.root, "rev-parse", "HEAD"]) |> String.trim()

    {:ok, repository: repository, sha: sha}
  end

  describe "run/2" do
    test "reads the check runs and statuses of HEAD and sums them up", %{
      repository: repository,
      sha: sha
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/commits/#{sha}/check-runs"

        Req.Test.json(conn, %{
          "total_count" => 2,
          "check_runs" => [
            %{
              "name" => "test",
              "status" => "completed",
              "conclusion" => "success",
              "html_url" => "u1"
            },
            %{
              "name" => "lint",
              "status" => "completed",
              "conclusion" => "failure",
              "html_url" => "u2"
            }
          ]
        })
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/commits/#{sha}/status"

        Req.Test.json(conn, %{
          "state" => "success",
          "statuses" => [%{"context" => "ci/x", "state" => "success", "target_url" => nil}]
        })
      end)

      assert %Value{value: checks, type: ChecksType} = NodeRunner.run(build_node(repository), [])

      assert checks == %{
               sha: sha,
               state: :failure,
               runs: [
                 %{name: "test", status: "completed", conclusion: "success", url: "u1"},
                 %{name: "lint", status: "completed", conclusion: "failure", url: "u2"}
               ],
               statuses: [%{context: "ci/x", state: "success", url: nil}]
             }
    end

    test "reports :pending while a check is going", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"check_runs" => [%{"name" => "test", "status" => "in_progress"}]})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"state" => "pending", "statuses" => []})
      end)

      assert %Value{value: %{state: :pending}} = NodeRunner.run(build_node(repository), [])
    end

    test "reports :failure when a check failed while another is going", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{
          "check_runs" => [
            %{"name" => "lint", "status" => "in_progress"},
            %{"name" => "test", "status" => "completed", "conclusion" => "failure"}
          ]
        })
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"state" => "pending", "statuses" => []})
      end)

      assert %Value{value: %{state: :failure}} = NodeRunner.run(build_node(repository), [])
    end

    test "reports :none for a commit without checks", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, %{"check_runs" => []}) end)

      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"state" => "pending", "statuses" => []})
      end)

      assert %Value{value: %{state: :none}} = NodeRunner.run(build_node(repository), [])
    end

    test "reads a named commit instead of HEAD", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/commits/deadbeef/check-runs"
        Req.Test.json(conn, %{"check_runs" => []})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"state" => "success", "statuses" => []})
      end)

      node = build_node(repository, %{sha: {"deadbeef", StringType}})
      assert %Value{value: %{sha: "deadbeef", state: :none}} = NodeRunner.run(node, [])
    end

    test "reports a rejected request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.metadata[:status] == 404
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "get_checks",
      runner: GetChecks,
      type: ChecksType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
