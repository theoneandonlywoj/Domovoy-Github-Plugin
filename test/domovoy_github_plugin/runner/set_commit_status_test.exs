defmodule DomovoyGithubPlugin.Runner.SetCommitStatusTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.SetCommitStatus
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Test.Repository
  alias DomovoyGithubPlugin.Type.CommitStatus, as: CommitStatusType

  setup :stub_requests

  setup do
    repository = Github.repository!()
    sha = Repository.git!(["-C", repository.root, "rev-parse", "HEAD"]) |> String.trim()

    {:ok, repository: repository, sha: sha}
  end

  describe "run/2" do
    test "sets a status on HEAD with the default context", %{repository: repository, sha: sha} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/statuses/#{sha}"

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body) == %{
                 "state" => "success",
                 "context" => "domovoy",
                 "description" => "All good"
               }

        Req.Test.json(conn, %{"state" => "success", "context" => "domovoy", "target_url" => nil})
      end)

      node =
        build_node(repository, %{
          state: {"success", StringType},
          description: {"All good", StringType}
        })

      assert %Value{value: status, type: CommitStatusType} = NodeRunner.run(node, [])
      assert status == %{sha: sha, state: "success", context: "domovoy", url: nil}
    end

    test "sends a context, a target url, and a named commit", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/statuses/deadbeef"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = JSON.decode!(body)
        assert payload["context"] == "domovoy/deploy"
        assert payload["target_url"] == "https://example.com/run/1"
        refute Map.has_key?(payload, "description")

        Req.Test.json(conn, %{
          "state" => "pending",
          "context" => "domovoy/deploy",
          "target_url" => "https://example.com/run/1"
        })
      end)

      node =
        build_node(repository, %{
          state: {"pending", StringType},
          context: {"domovoy/deploy", StringType},
          target_url: {"https://example.com/run/1", StringType},
          sha: {"deadbeef", StringType}
        })

      assert %Value{value: %{sha: "deadbeef", url: "https://example.com/run/1"}} =
               NodeRunner.run(node, [])
    end

    test "refuses a state GitHub does not accept, without calling GitHub", %{
      repository: repository
    } do
      node = build_node(repository, %{state: {"done", StringType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_invalid_commit_status_state
      assert error.metadata[:allowed_states] == ["error", "failure", "pending", "success"]
    end

    test "reports a rejected request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "Forbidden"})
      end)

      node = build_node(repository, %{state: {"success", StringType}})

      assert %Error{type: :github_request_failed} = NodeRunner.run(node, [])
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides) do
    Node.new(%{
      name: "set_status",
      runner: SetCommitStatus,
      type: CommitStatusType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
