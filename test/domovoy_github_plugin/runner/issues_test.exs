defmodule DomovoyGithubPlugin.Runner.IssuesTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.CreateIssue
  alias DomovoyGithubPlugin.Runner.GetIssue
  alias DomovoyGithubPlugin.Runner.UpdateIssue
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType
  alias DomovoyGithubPlugin.Type.Issue, as: IssueType
  alias DomovoyGithubPlugin.Type.Labels, as: LabelsType

  doctest CreateIssue, only: [issue: 1]

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "CreateIssue" do
    test "opens an issue with a body, labels, and assignees", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/issues"

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body) == %{
                 "title" => "Flaky test",
                 "body" => "## Where\n\nCI",
                 "labels" => ["bug"],
                 "assignees" => []
               }

        Req.Test.json(conn, issue_entry(%{"number" => 9, "title" => "Flaky test"}))
      end)

      blocks = [%{type: "heading", text: "Where"}, "CI"]

      node =
        build_node(CreateIssue, repository, %{
          title: {"Flaky test", StringType},
          body: {blocks, CommentBodyType},
          labels: {["bug"], LabelsType}
        })

      assert %Value{value: issue, type: IssueType} = NodeRunner.run(node, [])
      assert issue.number == 9
      assert issue.title == "Flaky test"
      assert issue.state == :open
      assert issue.labels == ["bug"]
    end

    test "rejects a blank title before calling GitHub", %{repository: repository} do
      node = build_node(CreateIssue, repository, %{title: {" ", StringType}})

      assert %Error{type: :invalid_input} = NodeRunner.run(node, [])
    end
  end

  describe "GetIssue" do
    test "reads the issue", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/issues/9"
        Req.Test.json(conn, issue_entry(%{"state" => "closed"}))
      end)

      node = build_node(GetIssue, repository, %{number: {9, IntegerType}})

      assert %Value{value: %{number: 9, state: :closed}} = NodeRunner.run(node, [])
    end

    test "reports a number that names nothing", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      node = build_node(GetIssue, repository, %{number: {99, IntegerType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_issue_not_found
      assert error.metadata[:number] == 99
    end
  end

  describe "UpdateIssue" do
    test "sends only the inputs the caller gave", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/repos/owner/repo/issues/9"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"state" => "closed"}

        Req.Test.json(conn, issue_entry(%{"state" => "closed"}))
      end)

      node =
        build_node(UpdateIssue, repository, %{
          number: {9, IntegerType},
          state: {"closed", StringType}
        })

      assert %Value{value: %{state: :closed}} = NodeRunner.run(node, [])
    end

    test "replaces labels and the title", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"title" => "New", "labels" => ["a", "b"]}
        Req.Test.json(conn, issue_entry(%{"title" => "New"}))
      end)

      node =
        build_node(UpdateIssue, repository, %{
          number: {9, IntegerType},
          title: {"New", StringType},
          labels: {["a", "b"], LabelsType}
        })

      assert %Value{value: %{title: "New"}} = NodeRunner.run(node, [])
    end

    test "reports a number that names nothing", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      node = build_node(UpdateIssue, repository, %{number: {99, IntegerType}})

      assert %Error{type: :github_issue_not_found} = NodeRunner.run(node, [])
    end
  end

  @spec issue_entry(map()) :: map()
  defp issue_entry(overrides) do
    Map.merge(
      %{
        "number" => 9,
        "title" => "Flaky test",
        "body" => "It fails.",
        "state" => "open",
        "labels" => [%{"name" => "bug"}],
        "assignees" => [],
        "html_url" => "https://github.com/owner/repo/issues/9"
      },
      overrides
    )
  end

  @spec build_node(module(), map(), map()) :: Node.t()
  defp build_node(runner, repository, overrides) do
    Node.new(%{
      name: "issue",
      runner: runner,
      type: IssueType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
