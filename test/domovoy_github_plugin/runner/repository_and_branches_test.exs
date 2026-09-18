defmodule DomovoyGithubPlugin.Runner.RepositoryAndBranchesTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.CompareBranches
  alias DomovoyGithubPlugin.Runner.DeleteRemoteBranch
  alias DomovoyGithubPlugin.Runner.GetBranch
  alias DomovoyGithubPlugin.Runner.GetRepository
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.Branch, as: BranchType
  alias DomovoyGithubPlugin.Type.BranchDeletion, as: BranchDeletionType
  alias DomovoyGithubPlugin.Type.Comparison, as: ComparisonType
  alias DomovoyGithubPlugin.Type.Repository, as: RepositoryType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "GetRepository" do
    test "reads the repository", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo"

        Req.Test.json(conn, %{
          "full_name" => "owner/repo",
          "default_branch" => "main",
          "private" => true,
          "html_url" => "https://github.com/owner/repo"
        })
      end)

      node = build_node(GetRepository, RepositoryType, repository, %{})

      assert %Value{value: value, type: RepositoryType} = NodeRunner.run(node, [])

      assert value == %{
               full_name: "owner/repo",
               default_branch: "main",
               private: true,
               url: "https://github.com/owner/repo"
             }
    end

    test "reports a rejected request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      node = build_node(GetRepository, RepositoryType, repository, %{})

      assert %Error{type: :github_request_failed} = NodeRunner.run(node, [])
    end
  end

  describe "GetBranch" do
    test "reads the current branch by default", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/branches/main"

        Req.Test.json(conn, %{
          "name" => "main",
          "commit" => %{"sha" => "abc123"},
          "protected" => true
        })
      end)

      node = build_node(GetBranch, BranchType, repository, %{})

      assert %Value{value: %{name: "main", sha: "abc123", protected: true}} =
               NodeRunner.run(node, [])
    end

    test "reports a branch GitHub does not have", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/branches/feat%2Fsearch"
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Branch not found"})
      end)

      node = build_node(GetBranch, BranchType, repository, %{branch: {"feat/search", StringType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_branch_not_found
      assert error.metadata[:branch] == "feat/search"
    end
  end

  describe "CompareBranches" do
    test "compares the current branch against the default branch", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo"
        Req.Test.json(conn, %{"default_branch" => "develop"})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/compare/develop...main"

        Req.Test.json(conn, %{
          "status" => "diverged",
          "ahead_by" => 2,
          "behind_by" => 5,
          "total_commits" => 2
        })
      end)

      node = build_node(CompareBranches, ComparisonType, repository, %{})

      assert %Value{value: comparison, type: ComparisonType} = NodeRunner.run(node, [])

      assert comparison == %{
               base: "develop",
               head: "main",
               status: :diverged,
               ahead_by: 2,
               behind_by: 5,
               total_commits: 2
             }
    end

    test "compares two named refs without reading the repository", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/compare/v1.0.0...v1.1.0"

        Req.Test.json(conn, %{
          "status" => "ahead",
          "ahead_by" => 9,
          "behind_by" => 0,
          "total_commits" => 9
        })
      end)

      node =
        build_node(CompareBranches, ComparisonType, repository, %{
          base: {"v1.0.0", StringType},
          head: {"v1.1.0", StringType}
        })

      assert %Value{value: %{status: :ahead, ahead_by: 9}} = NodeRunner.run(node, [])
    end

    test "reports a head GitHub does not have", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      node =
        build_node(CompareBranches, ComparisonType, repository, %{
          base: {"main", StringType},
          head: {"gone", StringType}
        })

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_branch_not_found
      assert error.metadata[:branch] == "gone"
    end
  end

  describe "DeleteRemoteBranch" do
    test "deletes the branch", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/repos/owner/repo/git/refs/heads/feat"
        Plug.Conn.send_resp(conn, 204, "")
      end)

      node =
        build_node(DeleteRemoteBranch, BranchDeletionType, repository, %{
          branch: {"feat", StringType}
        })

      assert %Value{value: %{branch: "feat", deleted: true}, type: BranchDeletionType} =
               NodeRunner.run(node, [])
    end

    test "reports a branch GitHub does not have", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{"message" => "Reference does not exist"})
      end)

      node =
        build_node(DeleteRemoteBranch, BranchDeletionType, repository, %{
          branch: {"gone", StringType}
        })

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_branch_not_found
      assert error.metadata[:branch] == "gone"
    end

    test "reports a protected branch as a request failure", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{"message" => "Cannot delete a protected branch"})
      end)

      node =
        build_node(DeleteRemoteBranch, BranchDeletionType, repository, %{
          branch: {"main", StringType}
        })

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_request_failed
      assert error.metadata[:status] == 422
    end
  end

  @spec build_node(module(), module(), map(), map()) :: Node.t()
  defp build_node(runner, type, repository, overrides) do
    Node.new(%{
      name: "repository",
      runner: runner,
      type: type,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
