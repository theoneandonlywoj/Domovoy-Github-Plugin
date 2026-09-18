defmodule DomovoyGithubPlugin.Runner.GetPrTest do
  use ExUnit.Case

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Capabilities
  alias DomovoyGithubPlugin.Runner.GetPr
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Test.Repository
  alias DomovoyGithubPlugin.Type.PullRequest, as: PullRequestType

  setup context do
    previous_options = Req.default_options()
    Req.default_options(plug: {Req.Test, __MODULE__}, retry: false)
    Req.Test.set_req_test_from_context(context)
    Req.Test.verify_on_exit!()

    repository = Repository.create!(remote?: false)
    Repository.git!(["-C", repository.root, "remote", "add", "origin", origin()])
    write_config!(repository.root, ~s({"access_token":"token"}))

    on_exit(fn ->
      Req.default_options(previous_options)
      File.rm_rf(repository.parent)
    end)

    {:ok, repository: repository}
  end

  describe "run/2" do
    test "returns the pull request for the current branch, newest first", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["head"] == "owner:main"
        assert conn.query_params["state"] == "all"
        assert conn.query_params["sort"] == "created"
        assert conn.query_params["direction"] == "desc"

        Req.Test.json(conn, [
          %{
            "number" => 7,
            "state" => "open",
            "merged_at" => nil,
            "title" => "feat: add search",
            "body" => "why",
            "html_url" => "https://github.com/owner/repo/pull/7"
          }
        ])
      end)

      assert %Value{value: pull, type: PullRequestType} =
               NodeRunner.run(build_node(repository), [])

      assert pull.state == :open
      assert pull.number == 7
      assert pull.title == "feat: add search"
      assert pull.body == "why"
      assert pull.url == "https://github.com/owner/repo/pull/7"
    end

    test "reports a merged pull request as :merged", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, [
          %{
            "number" => 7,
            "state" => "closed",
            "merged_at" => "2026-09-09T10:00:00Z",
            "title" => "feat: add search",
            "body" => "why",
            "html_url" => "https://github.com/owner/repo/pull/7"
          }
        ])
      end)

      assert %Value{value: pull} = NodeRunner.run(build_node(repository), [])
      assert pull.state == :merged
    end

    test "reports a pull request closed without a merge as :closed", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, [
          %{
            "number" => 7,
            "state" => "closed",
            "merged_at" => nil,
            "title" => "feat: add search",
            "body" => "why",
            "html_url" => "https://github.com/owner/repo/pull/7"
          }
        ])
      end)

      assert %Value{value: pull} = NodeRunner.run(build_node(repository), [])
      assert pull.state == :closed
    end

    test "the state argument narrows the search to open pull requests", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["state"] == "open"

        Req.Test.json(conn, [])
      end)

      assert %Value{value: pull} =
               NodeRunner.run(build_node(repository, %{state: {"open", StringType}}), [])

      assert pull.state == :not_found
    end

    test "refuses a state GitHub does not accept, without calling GitHub", %{
      repository: repository
    } do
      assert %Error{} =
               error =
               NodeRunner.run(build_node(repository, %{state: {"merged", StringType}}), [])

      assert error.type == :github_invalid_pull_request_state
      assert error.metadata[:state] == "merged"
      assert error.metadata[:allowed_states] == ["open", "closed", "all"]
    end

    test "succeeds with state: :not_found when the branch has no pull request", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, []) end)

      assert %Value{value: pull} = NodeRunner.run(build_node(repository), [])

      assert pull == %{
               state: :not_found,
               number: nil,
               title: nil,
               body: nil,
               url: nil
             }
    end

    test "reports a state it cannot match as :invalid_state", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, [
          %{
            "number" => 7,
            "state" => "merged",
            "merged_at" => nil,
            "title" => "feat: add search",
            "body" => "why",
            "html_url" => "https://github.com/owner/repo/pull/7"
          }
        ])
      end)

      assert %Value{value: pull} = NodeRunner.run(build_node(repository), [])
      assert pull.state == :invalid_state
      assert pull.number == 7
    end

    test "reads a numbered pull request instead of searching the branch", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/9"

        Req.Test.json(conn, %{
          "number" => 9,
          "state" => "closed",
          "merged_at" => "2026-09-09T10:00:00Z",
          "title" => "old",
          "body" => nil,
          "html_url" => "https://github.com/owner/repo/pull/9"
        })
      end)

      node = build_node(repository, %{number: {9, IntegerType}})

      assert %Value{value: pull} = NodeRunner.run(node, [])
      assert pull.state == :merged
      assert pull.number == 9
      assert pull.title == "old"
    end

    test "succeeds with state: :not_found for a number that names no pull request", %{
      repository: repository
    } do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      node = build_node(repository, %{number: {99, IntegerType}})

      assert %Value{value: %{state: :not_found, number: nil}} = NodeRunner.run(node, [])
    end

    test "reports GitHub's message as a contextual error", %{repository: repository} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "Bad credentials"})
      end)

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_request_failed
      assert error.reason == "Bad credentials"
      assert error.metadata[:status] == 401
    end

    test "reports an unparseable origin without calling GitHub", %{repository: repository} do
      Repository.git!([
        "-C",
        repository.root,
        "remote",
        "set-url",
        "origin",
        "git@gitlab.com:o/r"
      ])

      assert %Error{} = error = NodeRunner.run(build_node(repository), [])
      assert error.type == :github_origin_not_parsed
    end
  end

  @spec build_node(Repository.t(), map()) :: Node.t()
  defp build_node(repository, overrides \\ %{}) do
    Node.new(%{
      name: "get_pr",
      runner: GetPr,
      type: PullRequestType,
      args:
        Map.merge(
          %{working_directory: {repository.root, DirectoryType}},
          overrides
        )
    })
  end

  @spec origin() :: String.t()
  defp origin, do: "git@github.com:owner/repo.git"

  @spec write_config!(String.t(), String.t()) :: :ok
  defp write_config!(root, contents) do
    path = Path.join(root, Capabilities.config_relative_path())
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end
end
