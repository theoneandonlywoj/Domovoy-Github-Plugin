defmodule DomovoyGithubPlugin.CapabilitiesTest do
  use ExUnit.Case

  alias DomovoyCore.Error
  alias DomovoyGithubPlugin.Capabilities
  alias DomovoyGithubPlugin.Test.Repository

  doctest Capabilities, only: [config_file: 0, config_relative_path: 0]

  setup context do
    previous_options = Req.default_options()
    Req.default_options(plug: {Req.Test, __MODULE__}, retry: false)
    Req.Test.set_req_test_from_context(context)
    Req.Test.verify_on_exit!()

    on_exit(fn -> Req.default_options(previous_options) end)

    :ok
  end

  describe "config_relative_path/0 and find_config_path/1" do
    test "names the file under .domovoy/config and finds it up the tree" do
      assert Capabilities.config_relative_path() ==
               Path.join([".domovoy", "config", "github.json"])

      root = write_config!(~s({"access_token":"token"}))
      nested = Path.join([root, "apps", "domovoy"])
      File.mkdir_p!(nested)

      assert Capabilities.find_config_path(nested) ==
               Path.join(root, Capabilities.config_relative_path())
    end
  end

  describe "config readers" do
    test "read the access token and default base branch" do
      path = config_path!(~s({"access_token":" token ","default_base_branch":"main"}))

      assert Capabilities.access_token(path) == {:ok, "token"}
      assert Capabilities.default_base_branch(path) == {:ok, "main"}
    end

    test "report a missing token and base branch as :error" do
      path = config_path!(~s({}))

      assert Capabilities.access_token(path) == :error
      assert Capabilities.default_base_branch(path) == :error
    end

    test "fall back to the default timeouts when unset or invalid" do
      path = config_path!(~s({"access_token":"t","connect_timeout_ms":0}))

      assert Capabilities.connect_timeout_ms(path) == 15_000
      assert Capabilities.receive_timeout_ms(path) == 60_000
    end

    test "honour configured timeouts" do
      path =
        config_path!(~s({"access_token":"t","connect_timeout_ms":1000,"receive_timeout_ms":2000}))

      assert Capabilities.connect_timeout_ms(path) == 1_000
      assert Capabilities.receive_timeout_ms(path) == 2_000
    end
  end

  describe "current_repo/3" do
    test "parses an SSH origin" do
      repository = repository_with_origin!("git@github.com:theoneandonlywoj/Brownie.git")

      assert {:ok, repo} =
               Capabilities.current_repo(repository.root, "github", :working_directory)

      assert repo.owner == "theoneandonlywoj"
      assert repo.repo == "Brownie"
      assert repo.branch == "main"
    end

    test "parses an HTTPS origin, with and without the .git suffix" do
      repository = repository_with_origin!("https://github.com/theoneandonlywoj/Brownie.git")

      assert {:ok, %{owner: "theoneandonlywoj", repo: "Brownie"}} =
               Capabilities.current_repo(repository.root, "github", :working_directory)

      bare = repository_with_origin!("https://github.com/owner/repo")

      assert {:ok, %{owner: "owner", repo: "repo"}} =
               Capabilities.current_repo(bare.root, "github", :working_directory)
    end

    test "returns a contextual error for a remote that is not GitHub" do
      repository = repository_with_origin!("git@gitlab.com:owner/repo.git")

      assert {:error, %Error{} = error} =
               Capabilities.current_repo(repository.root, "github", :working_directory)

      assert error.type == :github_origin_not_parsed
      assert error.metadata[:remote_url] == "git@gitlab.com:owner/repo.git"
      assert error.metadata[:node_name] == "github"
      assert error.metadata[:field_name] == :working_directory
    end

    test "returns a Git command failure when there is no origin remote" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert {:error, %Error{} = error} =
               Capabilities.current_repo(repository.root, "github", :working_directory)

      assert error.type == :git_command_failed
    end
  end

  describe "list_open_pulls/4" do
    test "sends the head and state filters and returns the decoded body" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/repos/owner/repo/pulls"

        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["head"] == "owner:feature"
        assert conn.query_params["state"] == "open"

        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token"]

        Req.Test.json(conn, [%{"number" => 7, "html_url" => "https://github.com/pr/7"}])
      end)

      assert {:ok, [pull]} = Capabilities.list_open_pulls("owner", "repo", "owner:feature", root)
      assert pull["number"] == 7
    end

    test "returns an empty list when the branch has no open pull request" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, []) end)

      assert Capabilities.list_open_pulls("owner", "repo", "owner:feature", root) == {:ok, []}
    end

    test "reports GitHub's own message on a rejected request" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"message" => "Validation Failed"})
      end)

      assert Capabilities.list_open_pulls("owner", "repo", "owner:feature", root) ==
               {:error, "Validation Failed"}
    end

    test "reports a transport failure" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, message} =
               Capabilities.list_open_pulls("owner", "repo", "owner:feature", root)

      assert message =~ "GitHub API request failed"
    end

    test "explains how to set a missing access token, without calling GitHub" do
      root = write_config!(~s({}))

      assert {:error, message} =
               Capabilities.list_open_pulls("owner", "repo", "owner:feature", root)

      assert message =~ "access_token is not set"
      assert message =~ Capabilities.config_relative_path()
    end
  end

  describe "list_pulls/5" do
    test "sends the state it is given, and orders the newest pull request first" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls"

        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["head"] == "owner:feature"
        assert conn.query_params["state"] == "all"
        assert conn.query_params["sort"] == "created"
        assert conn.query_params["direction"] == "desc"

        Req.Test.json(conn, [%{"number" => 9, "state" => "closed"}])
      end)

      assert {:ok, [pull]} =
               Capabilities.list_pulls("owner", "repo", "owner:feature", "all", root)

      assert pull["number"] == 9
    end

    test "returns an empty list when the branch has no pull request in that state" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, []) end)

      assert Capabilities.list_pulls("owner", "repo", "owner:feature", "closed", root) ==
               {:ok, []}
    end
  end

  describe "create_pull/4 and update_pull/5" do
    test "post the pull request body" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/pulls"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body)["title"] == "feat: add search"

        Req.Test.json(conn, %{"number" => 7, "html_url" => "https://github.com/pr/7"})
      end)

      payload = %{"title" => "feat: add search", "body" => "why", "head" => "f", "base" => "main"}

      assert {:ok, pull} = Capabilities.create_pull("owner", "repo", payload, root)
      assert pull["number"] == 7
    end

    test "patch the numbered pull request" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/repos/owner/repo/pulls/7"

        Req.Test.json(conn, %{"number" => 7, "html_url" => "https://github.com/pr/7"})
      end)

      assert {:ok, %{"number" => 7}} =
               Capabilities.update_pull("owner", "repo", 7, %{"title" => "new"}, root)
    end
  end

  @spec repository_with_origin!(String.t()) :: Repository.t()
  defp repository_with_origin!(url) do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)

    Repository.git!(["-C", repository.root, "remote", "add", "origin", url])

    repository
  end

  @spec write_config!(String.t()) :: String.t()
  defp write_config!(contents) do
    root = Path.join(System.tmp_dir!(), "domovoy-github-#{System.unique_integer([:positive])}")
    path = Path.join(root, Capabilities.config_relative_path())

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    on_exit(fn -> File.rm_rf(root) end)

    root
  end

  @spec config_path!(String.t()) :: String.t()
  defp config_path!(contents) do
    contents |> write_config!() |> Path.join(Capabilities.config_relative_path())
  end
end
