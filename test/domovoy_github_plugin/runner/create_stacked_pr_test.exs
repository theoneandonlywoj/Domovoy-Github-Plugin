defmodule DomovoyGithubPlugin.Runner.CreateStackedPrTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.CreateStackedPr
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.PullRequestChange, as: PullRequestChangeType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "opens a pull request whose base is the parent branch", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["head"] == "owner:main"
        Req.Test.json(conn, [])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body) == %{
                 "title" => "feat: b",
                 "body" => "on top of a",
                 "head" => "main",
                 "base" => "feat-a",
                 "draft" => true
               }

        Req.Test.json(conn, Github.pull(%{"number" => 43}))
      end)

      node = build_node(repository, %{draft: {true, BooleanType}})

      assert %Value{value: change, type: PullRequestChangeType} = NodeRunner.run(node, [])

      assert change == %{
               action: "created",
               number: 43,
               url: "https://github.com/owner/repo/pull/7"
             }
    end

    test "re-bases the open pull request on the parent branch", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/repos/owner/repo/pulls/7"

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body) == %{
                 "title" => "feat: b",
                 "body" => "on top of a",
                 "base" => "feat-a"
               }

        Req.Test.json(conn, Github.pull())
      end)

      assert %Value{value: %{action: "updated", number: 7}} =
               NodeRunner.run(build_node(repository), [])
    end

    test "rejects a blank parent branch before calling GitHub", %{repository: repository} do
      node = build_node(repository, %{parent_branch: {" ", StringType}})

      assert %Error{type: :invalid_input, reason: [parent_branch: _]} = NodeRunner.run(node, [])
    end

    test "reports a parent branch GitHub does not know", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, []) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{
          "message" => "Validation Failed",
          "errors" => [%{"resource" => "PullRequest", "field" => "base", "code" => "invalid"}]
        })
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.reason == "Validation Failed; PullRequest.base invalid"
      assert error.metadata[:field_name] == :parent_branch
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "create_stacked_pr",
      runner: CreateStackedPr,
      type: PullRequestChangeType,
      args:
        Map.merge(
          %{
            working_directory: {repository.root, DirectoryType},
            title: {"feat: b", StringType},
            body: {"on top of a", StringType},
            parent_branch: {"feat-a", StringType}
          },
          overrides
        )
    })
  end
end
