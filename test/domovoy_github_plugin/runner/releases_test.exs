defmodule DomovoyGithubPlugin.Runner.ReleasesTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Runner.CreateRelease
  alias DomovoyGithubPlugin.Runner.GenerateReleaseNotes
  alias DomovoyGithubPlugin.Runner.GetLatestRelease
  alias DomovoyGithubPlugin.Runner.GetRelease
  alias DomovoyGithubPlugin.Test.Github
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType
  alias DomovoyGithubPlugin.Type.Release, as: ReleaseType
  alias DomovoyGithubPlugin.Type.ReleaseNotes, as: ReleaseNotesType

  doctest CreateRelease, only: [release: 1]

  setup :stub_requests

  setup do
    {:ok, repository: Github.repository!()}
  end

  describe "CreateRelease" do
    test "posts only the inputs the caller gave, with the flags", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/releases"

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body) == %{
                 "tag_name" => "v1.2.0",
                 "body" => "Notes",
                 "draft" => false,
                 "prerelease" => true,
                 "generate_release_notes" => true
               }

        Req.Test.json(conn, release_entry(%{"prerelease" => true}))
      end)

      node =
        build_node(CreateRelease, ReleaseType, repository, %{
          tag_name: {"v1.2.0", StringType},
          body: {"Notes", CommentBodyType},
          prerelease: {true, BooleanType},
          generate_release_notes: {true, BooleanType}
        })

      assert %Value{value: release, type: ReleaseType} = NodeRunner.run(node, [])
      assert release.tag_name == "v1.2.0"
      assert release.prerelease == true
      assert release.url == "https://github.com/owner/repo/releases/tag/v1.2.0"
    end

    test "reports a tag that already has a release", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{
          "message" => "Validation Failed",
          "errors" => [
            %{"resource" => "Release", "field" => "tag_name", "code" => "already_exists"}
          ]
        })
      end)

      node =
        build_node(CreateRelease, ReleaseType, repository, %{tag_name: {"v1.2.0", StringType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_request_failed
      assert error.reason == "Validation Failed; Release.tag_name already_exists"
    end
  end

  describe "GetLatestRelease and GetRelease" do
    test "read the latest release", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/releases/latest"
        Req.Test.json(conn, release_entry(%{}))
      end)

      node = build_node(GetLatestRelease, ReleaseType, repository, %{})

      assert %Value{value: %{tag_name: "v1.2.0", draft: false}} = NodeRunner.run(node, [])
    end

    test "read the release of a tag", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/releases/tags/v1.2.0"
        Req.Test.json(conn, release_entry(%{}))
      end)

      node = build_node(GetRelease, ReleaseType, repository, %{tag: {"v1.2.0", StringType}})

      assert %Value{value: %{tag_name: "v1.2.0"}} = NodeRunner.run(node, [])
    end

    test "report a repository without a release, and a tag without one", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      latest = build_node(GetLatestRelease, ReleaseType, repository, %{})
      assert %Error{} = error = NodeRunner.run(latest, [])
      assert error.type == :github_release_not_found
      assert error.metadata[:tag] == nil

      by_tag = build_node(GetRelease, ReleaseType, repository, %{tag: {"v9", StringType}})
      assert %Error{} = error = NodeRunner.run(by_tag, [])
      assert error.type == :github_release_not_found
      assert error.metadata[:tag] == "v9"
    end
  end

  describe "GenerateReleaseNotes" do
    test "asks GitHub for the notes of a tag", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/releases/generate-notes"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"tag_name" => "v1.2.0", "previous_tag_name" => "v1.1.0"}

        Req.Test.json(conn, %{"name" => "v1.2.0", "body" => "## What's Changed"})
      end)

      node =
        build_node(GenerateReleaseNotes, ReleaseNotesType, repository, %{
          tag_name: {"v1.2.0", StringType},
          previous_tag_name: {"v1.1.0", StringType}
        })

      assert %Value{value: notes, type: ReleaseNotesType} = NodeRunner.run(node, [])
      assert notes == %{name: "v1.2.0", body: "## What's Changed"}
    end

    test "reports a rejected request", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      node =
        build_node(GenerateReleaseNotes, ReleaseNotesType, repository, %{
          tag_name: {"v1.2.0", StringType}
        })

      assert %Error{type: :github_request_failed} = NodeRunner.run(node, [])
    end
  end

  @spec release_entry(map()) :: map()
  defp release_entry(overrides) do
    Map.merge(
      %{
        "id" => 1,
        "tag_name" => "v1.2.0",
        "name" => "v1.2.0",
        "body" => "Notes",
        "draft" => false,
        "prerelease" => false,
        "html_url" => "https://github.com/owner/repo/releases/tag/v1.2.0"
      },
      overrides
    )
  end

  @spec build_node(module(), module(), map(), map()) :: Node.t()
  defp build_node(runner, type, repository, overrides) do
    Node.new(%{
      name: "release",
      runner: runner,
      type: type,
      args: Map.merge(%{working_directory: {repository.root, DirectoryType}}, overrides)
    })
  end
end
