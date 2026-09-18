defmodule DomovoyGithubPlugin.Runner.CreateOrUpdatePrTest do
  use ExUnit.Case

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Capabilities
  alias DomovoyGithubPlugin.Runner.CreateOrUpdatePr
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Test.Repository
  alias DomovoyGithubPlugin.Type.PullRequestChange, as: PullRequestChangeType

  setup context do
    previous_options = Req.default_options()
    Req.default_options(plug: {Req.Test, __MODULE__}, retry: false)
    Req.Test.set_req_test_from_context(context)
    Req.Test.verify_on_exit!()

    repository = Repository.create!(remote?: false)

    Repository.git!([
      "-C",
      repository.root,
      "remote",
      "add",
      "origin",
      "git@github.com:owner/repo.git"
    ])

    write_config!(repository.root, ~s({"access_token":"token","default_base_branch":"main"}))

    on_exit(fn ->
      Req.default_options(previous_options)
      File.rm_rf(repository.parent)
    end)

    {:ok, repository: repository}
  end

  describe "run/2" do
    test "creates a pull request when the branch has none", %{repository: repository} do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case conn.method do
          "GET" ->
            Req.Test.json(conn, [])

          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            payload = JSON.decode!(body)

            assert payload["title"] == "feat: add search"
            assert payload["body"] == "why"
            assert payload["head"] == "main"
            assert payload["base"] == "main"
            assert payload["draft"] == false

            Req.Test.json(conn, %{
              "number" => 7,
              "html_url" => "https://github.com/owner/repo/pull/7"
            })
        end
      end)

      assert %Value{value: change, type: PullRequestChangeType} =
               NodeRunner.run(build_node(repository, %{}), [])

      assert change.action == "created"
      assert change.number == 7
      assert change.url == "https://github.com/owner/repo/pull/7"
    end

    test "updates the existing pull request when the branch already has one", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case conn.method do
          "GET" ->
            Req.Test.json(conn, [%{"number" => 7}])

          "PATCH" ->
            assert conn.request_path == "/repos/owner/repo/pulls/7"

            {:ok, body, conn} = Plug.Conn.read_body(conn)
            payload = JSON.decode!(body)

            assert payload["title"] == "feat: add search"
            refute Map.has_key?(payload, "head")

            Req.Test.json(conn, %{
              "number" => 7,
              "html_url" => "https://github.com/owner/repo/pull/7"
            })
        end
      end)

      assert %Value{value: change} = NodeRunner.run(build_node(repository, %{}), [])
      assert change.action == "updated"
      assert change.number == 7
    end

    test "opens a draft pull request when asked", %{repository: repository} do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case conn.method do
          "GET" ->
            Req.Test.json(conn, [])

          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            assert JSON.decode!(body)["draft"] == true

            Req.Test.json(conn, %{"number" => 1, "html_url" => "u"})
        end
      end)

      node = build_node(repository, %{draft: {true, BooleanType}})

      assert %Value{value: %{action: "created"}} = NodeRunner.run(node, [])
    end

    test "does not send draft on an update", %{repository: repository} do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case conn.method do
          "GET" ->
            Req.Test.json(conn, [%{"number" => 7}])

          "PATCH" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            refute Map.has_key?(JSON.decode!(body), "draft")

            Req.Test.json(conn, %{"number" => 7, "html_url" => "u"})
        end
      end)

      node = build_node(repository, %{draft: {true, BooleanType}})

      assert %Value{value: %{action: "updated"}} = NodeRunner.run(node, [])
    end

    test "falls back to default_base_branch from the config", %{repository: repository} do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case conn.method do
          "GET" ->
            Req.Test.json(conn, [])

          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            assert JSON.decode!(body)["base"] == "main"

            Req.Test.json(conn, %{"number" => 1, "html_url" => "u"})
        end
      end)

      assert %Value{value: %{action: "created"}} =
               NodeRunner.run(build_node(repository, %{}), [])
    end

    test "prefers an explicit base branch over the configured one", %{repository: repository} do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case conn.method do
          "GET" ->
            Req.Test.json(conn, [])

          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            assert JSON.decode!(body)["base"] == "develop"

            Req.Test.json(conn, %{"number" => 1, "html_url" => "u"})
        end
      end)

      node = build_node(repository, %{base_branch: {"develop", StringType}})

      assert %Value{value: %{action: "created"}} = NodeRunner.run(node, [])
    end

    test "takes the title from a named dependency", %{repository: repository} do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case conn.method do
          "GET" ->
            Req.Test.json(conn, [])

          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            assert JSON.decode!(body)["title"] == "wired title"

            Req.Test.json(conn, %{"number" => 1, "html_url" => "u"})
        end
      end)

      node =
        build_node(
          repository,
          %{},
          %{title: {"computed", StringType}}
        )

      computed = Value.cast!("wired title", StringType)

      assert %Value{} = NodeRunner.run(node, [{"computed", computed}])
    end

    test "reports a missing base branch when neither supplied nor configured", %{
      repository: repository
    } do
      write_config!(repository.root, ~s({"access_token":"token"}))

      assert %Error{} = error = NodeRunner.run(build_node(repository, %{}), [])
      assert error.type == :github_create_or_update_pr_failed
      assert error.reason =~ "without a base branch"
    end

    test "rejects a blank title before calling GitHub", %{repository: repository} do
      node =
        Node.new(%{
          name: "create_or_update_pr",
          runner: CreateOrUpdatePr,
          type: PullRequestChangeType,
          args: %{
            working_directory: {repository.root, DirectoryType},
            title: {" ", StringType},
            body: {"why", StringType}
          }
        })

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :invalid_input
      assert [title: {"can't be blank", _}] = error.reason
    end

    test "reports GitHub's message when creation is rejected", %{repository: repository} do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case conn.method do
          "GET" ->
            Req.Test.json(conn, [])

          "POST" ->
            conn
            |> Plug.Conn.put_status(422)
            |> Req.Test.json(%{"message" => "Validation Failed"})
        end
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository, %{}), [])
      assert error.type == :github_request_failed
      assert error.reason == "Validation Failed"
    end
  end

  @spec build_node(repository :: Repository.t(), overrides :: map(), bind :: map()) :: Node.t()
  defp build_node(repository, overrides, bind \\ %{}) do
    args =
      Map.merge(
        %{
          working_directory: {repository.root, DirectoryType},
          title: {"feat: add search", StringType},
          body: {"why", StringType}
        },
        overrides
      )
      |> Map.drop(Map.keys(bind))

    Node.new(%{
      name: "create_or_update_pr",
      runner: CreateOrUpdatePr,
      type: PullRequestChangeType,
      args: args,
      bind: bind
    })
  end

  @spec write_config!(String.t(), String.t()) :: :ok
  defp write_config!(root, contents) do
    path = Path.join(root, Capabilities.config_relative_path())
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end
end
