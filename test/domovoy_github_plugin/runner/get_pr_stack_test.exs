defmodule DomovoyGithubPlugin.Runner.GetPrStackTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.GetPrStack
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.Stack, as: StackType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "walks up to the root and down to the leaf", %{repository: repository} do
      # Stack: 41 (feat-a <- main) <- 42 (feat-b <- feat-a) <- 43 (feat-c <- feat-b)
      # The current branch is feat-b, number 42.
      stub_pull(query: %{"head" => "owner:main"}, answer: [pull(42, "feat-b", "feat-a")])
      stub_repository("main")
      stub_pull(query: %{"head" => "owner:feat-a"}, answer: [pull(41, "feat-a", "main")])
      stub_pull(query: %{"base" => "feat-b"}, answer: [pull(43, "feat-c", "feat-b")])
      stub_pull(query: %{"base" => "feat-c"}, answer: [])

      assert %Value{value: stack, type: StackType} = NodeRunner.run(build_node(repository), [])

      assert stack == %{
               base: "main",
               current: 42,
               pulls: [
                 %{number: 41, head: "feat-a", base: "main", url: "https://github.com/pr/41"},
                 %{number: 42, head: "feat-b", base: "feat-a", url: "https://github.com/pr/42"},
                 %{number: 43, head: "feat-c", base: "feat-b", url: "https://github.com/pr/43"}
               ]
             }
    end

    test "reports a stack of one for a pull request on the default branch", %{
      repository: repository
    } do
      stub_pull(
        query: %{"number" => 7},
        path: "/repos/owner/repo/pulls/7",
        answer: pull(7, "feat", "main")
      )

      stub_repository("main")
      stub_pull(query: %{"base" => "feat"}, answer: [])

      node = build_node(repository, %{number: {7, IntegerType}})

      assert %Value{value: %{current: 7, pulls: [%{number: 7}]}} = NodeRunner.run(node, [])
    end

    test "treats a base without an open pull request as the root", %{repository: repository} do
      stub_pull(query: %{"head" => "owner:main"}, answer: [pull(42, "feat-b", "release")])
      stub_repository("main")
      stub_pull(query: %{"head" => "owner:release"}, answer: [])
      stub_pull(query: %{"base" => "feat-b"}, answer: [])

      assert %Value{value: %{pulls: [%{number: 42, base: "release"}]}} =
               NodeRunner.run(build_node(repository), [])
    end

    test "reports a chain of bases that loops", %{repository: repository} do
      stub_pull(query: %{"head" => "owner:main"}, answer: [pull(42, "feat-b", "feat-a")])
      stub_repository("main")
      stub_pull(query: %{"head" => "owner:feat-a"}, answer: [pull(41, "feat-a", "feat-b")])

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_stack_cycle_detected
      assert error.metadata[:branches] == ["feat-b", "feat-a", "feat-b"]
    end

    test "reports a rejected request while walking", %{repository: repository} do
      stub_pull(query: %{"head" => "owner:main"}, answer: [pull(42, "feat-b", "feat-a")])
      stub_repository("main")

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "Server Error"})
      end)

      assert %Error{type: :github_request_failed} = NodeRunner.run(build_node(repository), [])
    end
  end

  @spec stub_pull(keyword()) :: :ok
  defp stub_pull(opts) do
    query = Keyword.fetch!(opts, :query)
    answer = Keyword.fetch!(opts, :answer)
    path = Keyword.get(opts, :path, "/repos/owner/repo/pulls")

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == path
      conn = Plug.Conn.fetch_query_params(conn)

      for {key, value} <- query, key != "number" do
        assert conn.query_params[key] == value
      end

      Req.Test.json(conn, answer)
    end)

    :ok
  end

  @spec stub_repository(String.t()) :: :ok
  defp stub_repository(default_branch) do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/repos/owner/repo"
      Req.Test.json(conn, %{"default_branch" => default_branch})
    end)

    :ok
  end

  @spec pull(integer(), String.t(), String.t()) :: map()
  defp pull(number, head, base) do
    Github.pull(%{
      "number" => number,
      "html_url" => "https://github.com/pr/#{number}",
      "head" => %{"ref" => head, "sha" => "sha#{number}"},
      "base" => %{"ref" => base}
    })
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "get_pr_stack",
      runner: GetPrStack,
      type: StackType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
