defmodule DomovoyGithubPlugin.Runner.CreateOrUpdatePrCommentTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.CreateOrUpdatePrComment
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType
  alias DomovoyGithubPlugin.Type.CommentChange, as: CommentChangeType
  alias DomovoyGithubPlugin.Type.CommentKey, as: CommentKeyType

  doctest CreateOrUpdatePrComment, only: [marker: 1]

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "run/2" do
    test "writes a marked comment when the pull request has none with the key", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/issues/7/comments"
        Req.Test.json(conn, [%{"id" => 1, "body" => "unrelated"}])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/issues/7/comments"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"body" => "<!-- domovoy:checks -->\nAll green."}

        Req.Test.json(conn, %{"id" => 1001, "html_url" => "https://c/1001"})
      end)

      assert %Value{value: change, type: CommentChangeType} =
               NodeRunner.run(build_node(repository), [])

      assert change == %{action: "created", id: 1001, url: "https://c/1001"}
    end

    test "replaces the marked comment when the pull request has one", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, [
          %{"id" => 1, "body" => "unrelated"},
          %{"id" => 1001, "body" => "<!-- domovoy:checks -->\nold text"}
        ])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/repos/owner/repo/issues/comments/1001"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body)["body"] =~ "All green."

        Req.Test.json(conn, %{"id" => 1001, "html_url" => "https://c/1001"})
      end)

      assert %Value{value: %{action: "updated", id: 1001}} =
               NodeRunner.run(build_node(repository), [])
    end

    test "renders a body made of blocks", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, []) end)

      Req.Test.expect(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body)["body"] ==
                 "<!-- domovoy:checks -->\n## Checks\n\n> failed: format"

        Req.Test.json(conn, %{"id" => 1, "html_url" => "u"})
      end)

      blocks = [%{type: "heading", text: "Checks"}, %{type: "quote", text: "failed: format"}]
      node = build_node(repository, %{body: {blocks, CommentBodyType}})

      assert %Value{value: %{action: "created"}} = NodeRunner.run(node, [])
    end

    test "rejects a blank key before calling GitHub", %{repository: repository} do
      node = build_node(repository, %{key: {"", CommentKeyType}})

      assert %Error{type: :invalid_input} = NodeRunner.run(node, [])
    end

    test "rejects a key that would break the marker before calling GitHub", %{
      repository: repository
    } do
      node = build_node(repository, %{key: {"checks -->", CommentKeyType}})

      assert %Error{type: :invalid_input} = NodeRunner.run(node, [])
    end

    test "reports a rejected write with its status", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, []) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "Forbidden"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.metadata[:status] == 403
      assert error.metadata[:field_name] == :body
    end
  end

  @spec build_node(repository :: map(), overrides :: map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "report",
      runner: CreateOrUpdatePrComment,
      type: CommentChangeType,
      args:
        Map.merge(
          %{
            working_directory: {repository.root, DirectoryType},
            key: {"checks", CommentKeyType},
            body: {"All green.", CommentBodyType}
          },
          overrides
        )
    })
  end
end
