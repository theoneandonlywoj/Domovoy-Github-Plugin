defmodule DomovoyGithubPlugin.Runner.PrLabelsTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.AddPrLabels
  alias DomovoyGithubPlugin.Runner.RemovePrLabel
  alias DomovoyGithubPlugin.Runner.SetPrLabels
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.Labels, as: LabelsType

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "AddPrLabels" do
    test "posts the labels and lists every label after the change", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/issues/7/labels"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"labels" => ["ready"]}

        Req.Test.json(conn, [%{"name" => "bug"}, %{"name" => "ready"}])
      end)

      node = build_node(AddPrLabels, repository, %{labels: {["ready"], LabelsType}})

      assert %Value{value: ["bug", "ready"], type: LabelsType} = NodeRunner.run(node, [])
    end

    test "rejects a blank label before calling GitHub", %{repository: repository} do
      node = build_node(AddPrLabels, repository, %{labels: {[""], LabelsType}})

      assert %Error{type: :invalid_input} = NodeRunner.run(node, [])
    end
  end

  describe "SetPrLabels" do
    test "puts the labels, and an empty list clears them", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/repos/owner/repo/issues/7/labels"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"labels" => []}

        Req.Test.json(conn, [])
      end)

      node = build_node(SetPrLabels, repository, %{labels: {[], LabelsType}})

      assert %Value{value: []} = NodeRunner.run(node, [])
    end

    test "reports a rejected request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "Forbidden"})
      end)

      node = build_node(SetPrLabels, repository, %{labels: {["x"], LabelsType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_request_failed
      assert error.metadata[:field_name] == :labels
    end
  end

  describe "RemovePrLabel" do
    test "deletes the label and lists the ones that remain", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/repos/owner/repo/issues/7/labels/help%20wanted"

        Req.Test.json(conn, [%{"name" => "bug"}])
      end)

      node = build_node(RemovePrLabel, repository, %{label: {"help wanted", StringType}})

      assert %Value{value: ["bug"], type: LabelsType} = NodeRunner.run(node, [])
    end

    test "reports a label the pull request does not have", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [Github.pull()]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Label does not exist"})
      end)

      node = build_node(RemovePrLabel, repository, %{label: {"wip", StringType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_label_not_found
      assert error.metadata[:label] == "wip"
      assert error.metadata[:number] == 7
    end
  end

  @spec build_node(module(), map(), map()) :: Node.t()
  defp build_node(runner, repository, overrides) do
    Node.new(%{
      name: "labels",
      runner: runner,
      type: LabelsType,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
