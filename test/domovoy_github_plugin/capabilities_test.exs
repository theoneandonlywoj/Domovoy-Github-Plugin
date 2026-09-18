defmodule DomovoyGithubPlugin.CapabilitiesTest do
  use ExUnit.Case

  alias DomovoyCore.Error
  alias DomovoyGithubPlugin.Capabilities
  alias DomovoyGithubPlugin.Test.Repository

  doctest Capabilities,
    only: [config_file: 0, config_relative_path: 0, access_token: 1, connect_timeout_ms: 1]

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

    test "read a decoded configuration map without touching the disk" do
      config = %{
        "access_token" => " token ",
        "default_base_branch" => "main",
        "connect_timeout_ms" => 1_000,
        "receive_timeout_ms" => 2_000
      }

      assert Capabilities.access_token(config) == {:ok, "token"}
      assert Capabilities.default_base_branch(config) == {:ok, "main"}
      assert Capabilities.connect_timeout_ms(config) == 1_000
      assert Capabilities.receive_timeout_ms(config) == 2_000

      assert Capabilities.access_token(%{}) == :error
      assert Capabilities.default_base_branch(%{}) == :error
      assert Capabilities.connect_timeout_ms(%{"connect_timeout_ms" => "1000"}) == 15_000
      assert Capabilities.receive_timeout_ms(%{}) == 60_000
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
               {:error, %{status: 422, message: "Validation Failed"}}
    end

    test "reports a transport failure" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, %{status: nil, message: message}} =
               Capabilities.list_open_pulls("owner", "repo", "owner:feature", root)

      assert message =~ "GitHub API request failed"
    end

    test "explains how to set a missing access token, without calling GitHub" do
      root = write_config!(~s({}))

      assert {:error, %{status: nil, message: message}} =
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

  describe "get_pull/4" do
    test "reads the numbered pull request" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/repos/owner/repo/pulls/7"

        Req.Test.json(conn, %{"number" => 7, "state" => "open"})
      end)

      assert {:ok, %{"number" => 7}} = Capabilities.get_pull("owner", "repo", 7, root)
    end

    test "reports a missing pull request with status 404" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      assert Capabilities.get_pull("owner", "repo", 7, root) ==
               {:error, %{status: 404, message: "Not Found"}}
    end
  end

  describe "get_repository/3 and list_pulls_by_base/5" do
    test "read the repository and the children of a branch" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo"
        Req.Test.json(conn, %{"default_branch" => "main"})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls"
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["base"] == "feat-a"
        assert conn.query_params["state"] == "open"
        assert conn.query_params["sort"] == "created"
        assert conn.query_params["direction"] == "desc"
        Req.Test.json(conn, [%{"number" => 2}])
      end)

      assert {:ok, %{"default_branch" => "main"}} =
               Capabilities.get_repository("owner", "repo", root)

      assert {:ok, [%{"number" => 2}]} =
               Capabilities.list_pulls_by_base("owner", "repo", "feat-a", "open", root)
    end
  end

  describe "upsert_pull/6" do
    test "creates when the branch has no open pull request" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["head"] == "owner:feat"
        Req.Test.json(conn, [])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"title" => "t", "head" => "feat"}
        Req.Test.json(conn, %{"number" => 1})
      end)

      create = %{"title" => "t", "head" => "feat"}
      update = %{"title" => "t"}

      assert Capabilities.upsert_pull("owner", "repo", "feat", create, update, root) ==
               {:ok, {:created, %{"number" => 1}}}
    end

    test "updates the newest open pull request of the branch" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, [%{"number" => 5}]) end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/repos/owner/repo/pulls/5"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"title" => "t"}
        Req.Test.json(conn, %{"number" => 5})
      end)

      assert Capabilities.upsert_pull("owner", "repo", "feat", %{}, %{"title" => "t"}, root) ==
               {:ok, {:updated, %{"number" => 5}}}
    end

    test "passes a failure of the search through" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "Bad credentials"})
      end)

      assert Capabilities.upsert_pull("owner", "repo", "feat", %{}, %{}, root) ==
               {:error, %{status: 401, message: "Bad credentials"}}
    end
  end

  describe "pull request actions" do
    test "merge_pull/5 puts the merge body" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/repos/owner/repo/pulls/7/merge"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"merge_method" => "squash"}

        Req.Test.json(conn, %{"merged" => true, "sha" => "abc"})
      end)

      assert {:ok, %{"merged" => true}} =
               Capabilities.merge_pull("owner", "repo", 7, %{"merge_method" => "squash"}, root)
    end

    test "request_reviewers/5 posts the reviewers" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/pulls/7/requested_reviewers"
        Req.Test.json(conn, %{"number" => 7})
      end)

      assert {:ok, %{"number" => 7}} =
               Capabilities.request_reviewers("owner", "repo", 7, %{"reviewers" => ["a"]}, root)
    end

    test "update_pull_branch/4 puts to update-branch and accepts a 202" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/repos/owner/repo/pulls/7/update-branch"
        conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{"message" => "Updating"})
      end)

      assert {:ok, %{"message" => "Updating"}} =
               Capabilities.update_pull_branch("owner", "repo", 7, root)
    end

    test "list_pull_files/4 and list_pull_commits/4 page through the lists" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/7/files"
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["per_page"] == "100"
        Req.Test.json(conn, [%{"filename" => "a"}])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/7/commits"
        Req.Test.json(conn, [%{"sha" => "a"}])
      end)

      assert Capabilities.list_pull_files("owner", "repo", 7, root) ==
               {:ok, [%{"filename" => "a"}]}

      assert Capabilities.list_pull_commits("owner", "repo", 7, root) == {:ok, [%{"sha" => "a"}]}
    end

    test "mark_pull_ready_for_review/2 sends the mutation" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/graphql"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = JSON.decode!(body)
        assert payload["query"] =~ "markPullRequestReadyForReview"
        assert payload["variables"] == %{"id" => "PR_1"}

        Req.Test.json(conn, %{"data" => %{"markPullRequestReadyForReview" => %{}}})
      end)

      assert {:ok, %{"markPullRequestReadyForReview" => %{}}} =
               Capabilities.mark_pull_ready_for_review("PR_1", root)
    end
  end

  describe "comments and reviews" do
    test "list, create, and update conversation comments" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/issues/7/comments"
        Req.Test.json(conn, [%{"id" => 1}])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/issues/7/comments"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"body" => "hi"}
        Req.Test.json(conn, %{"id" => 2})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/repos/owner/repo/issues/comments/2"
        Req.Test.json(conn, %{"id" => 2})
      end)

      assert {:ok, [%{"id" => 1}]} = Capabilities.list_issue_comments("owner", "repo", 7, root)

      assert {:ok, %{"id" => 2}} =
               Capabilities.create_issue_comment("owner", "repo", 7, "hi", root)

      assert {:ok, %{"id" => 2}} =
               Capabilities.update_issue_comment("owner", "repo", 2, "yo", root)
    end

    test "create and list reviews, and write review comments and replies" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/pulls/7/reviews"
        Req.Test.json(conn, %{"id" => 5})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/7/reviews"
        Req.Test.json(conn, [%{"id" => 5}])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/pulls/7/comments"
        Req.Test.json(conn, %{"id" => 9})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/pulls/7/comments/9/replies"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"body" => "reply"}
        Req.Test.json(conn, %{"id" => 10})
      end)

      assert {:ok, %{"id" => 5}} =
               Capabilities.create_review("owner", "repo", 7, %{"event" => "APPROVE"}, root)

      assert {:ok, [%{"id" => 5}]} = Capabilities.list_reviews("owner", "repo", 7, root)

      assert {:ok, %{"id" => 9}} =
               Capabilities.create_review_comment("owner", "repo", 7, %{"body" => "b"}, root)

      assert {:ok, %{"id" => 10}} =
               Capabilities.reply_to_review_comment("owner", "repo", 7, 9, "reply", root)
    end

    test "list and resolve review threads through GraphQL" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = JSON.decode!(body)
        assert payload["query"] =~ "reviewThreads"
        assert payload["variables"] == %{"owner" => "owner", "repo" => "repo", "number" => 7}
        Req.Test.json(conn, %{"data" => %{"repository" => nil}})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = JSON.decode!(body)
        assert payload["query"] =~ "resolveReviewThread"
        assert payload["variables"] == %{"id" => "PRRT_1"}
        Req.Test.json(conn, %{"data" => %{"resolveReviewThread" => nil}})
      end)

      assert {:ok, %{"repository" => nil}} =
               Capabilities.list_review_threads("owner", "repo", 7, root)

      assert {:ok, %{"resolveReviewThread" => nil}} =
               Capabilities.resolve_review_thread("PRRT_1", root)
    end
  end

  describe "checks and actions" do
    test "list check runs, read the combined status, and set a status" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/commits/abc/check-runs"
        Req.Test.json(conn, %{"check_runs" => [%{"name" => "ci"}]})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/commits/abc/status"
        Req.Test.json(conn, %{"state" => "success"})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/statuses/abc"
        Req.Test.json(conn, %{"state" => "success"})
      end)

      assert {:ok, [%{"name" => "ci"}]} =
               Capabilities.list_check_runs("owner", "repo", "abc", root)

      assert {:ok, %{"state" => "success"}} =
               Capabilities.get_combined_status("owner", "repo", "abc", root)

      assert {:ok, %{"state" => "success"}} =
               Capabilities.create_commit_status(
                 "owner",
                 "repo",
                 "abc",
                 %{"state" => "success"},
                 root
               )
    end

    test "list runs with and without a workflow, and read one run" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/actions/runs"
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["branch"] == "main"
        Req.Test.json(conn, %{"workflow_runs" => [%{"id" => 1}]})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/actions/workflows/ci.yml/runs"
        Req.Test.json(conn, %{"workflow_runs" => []})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/actions/runs/1"
        Req.Test.json(conn, %{"id" => 1})
      end)

      assert {:ok, [%{"id" => 1}]} =
               Capabilities.list_workflow_runs("owner", "repo", nil, [branch: "main"], root)

      assert {:ok, []} = Capabilities.list_workflow_runs("owner", "repo", "ci.yml", [], root)
      assert {:ok, %{"id" => 1}} = Capabilities.get_workflow_run("owner", "repo", 1, root)
    end

    test "reports a runs body without the list" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, %{"message" => "odd"}) end)

      assert {:error, %{status: nil, message: message}} =
               Capabilities.list_workflow_runs("owner", "repo", nil, [], root)

      assert message =~ "unexpected body"
    end

    test "dispatch a workflow, list jobs, and download logs" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/actions/workflows/ci.yml/dispatches"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"ref" => "main", "inputs" => %{"a" => "1"}}
        Plug.Conn.send_resp(conn, 204, "")
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/actions/runs/1/jobs"
        Req.Test.json(conn, %{"jobs" => [%{"id" => 9}]})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/actions/runs/1/logs"

        conn
        |> Plug.Conn.put_resp_content_type("application/zip")
        |> Plug.Conn.send_resp(200, "PK")
      end)

      assert {:ok, nil} =
               Capabilities.dispatch_workflow(
                 "owner",
                 "repo",
                 "ci.yml",
                 "main",
                 %{"a" => "1"},
                 root
               )

      assert {:ok, [%{"id" => 9}]} = Capabilities.list_workflow_jobs("owner", "repo", 1, root)
      assert {:ok, "PK"} = Capabilities.download_workflow_run_logs("owner", "repo", 1, root)
    end
  end

  describe "labels, assignees, and issues" do
    test "add, set, and remove labels, and add assignees" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/issues/7/labels"
        Req.Test.json(conn, [%{"name" => "a"}])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/repos/owner/repo/issues/7/labels"
        Req.Test.json(conn, [])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/repos/owner/repo/issues/7/labels/a"
        Req.Test.json(conn, [])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/issues/7/assignees"
        Req.Test.json(conn, %{"assignees" => [%{"login" => "x"}]})
      end)

      assert {:ok, [%{"name" => "a"}]} = Capabilities.add_labels("owner", "repo", 7, ["a"], root)
      assert {:ok, []} = Capabilities.set_labels("owner", "repo", 7, [], root)
      assert {:ok, []} = Capabilities.remove_label("owner", "repo", 7, "a", root)

      assert {:ok, %{"assignees" => _}} =
               Capabilities.add_assignees("owner", "repo", 7, ["x"], root)
    end

    test "create, get, and update an issue" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/issues"
        Req.Test.json(conn, %{"number" => 9})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/issues/9"
        Req.Test.json(conn, %{"number" => 9})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/repos/owner/repo/issues/9"
        Req.Test.json(conn, %{"number" => 9})
      end)

      assert {:ok, %{"number" => 9}} =
               Capabilities.create_issue("owner", "repo", %{"title" => "t"}, root)

      assert {:ok, %{"number" => 9}} = Capabilities.get_issue("owner", "repo", 9, root)
      assert {:ok, %{"number" => 9}} = Capabilities.update_issue("owner", "repo", 9, %{}, root)
    end
  end

  describe "releases, branches, and refs" do
    test "create, read, and write notes for releases" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/releases"
        Req.Test.json(conn, %{"id" => 1})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/releases/latest"
        Req.Test.json(conn, %{"id" => 1})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/releases/tags/v1.0.0"
        Req.Test.json(conn, %{"id" => 1})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/releases/generate-notes"
        Req.Test.json(conn, %{"name" => "v1", "body" => "b"})
      end)

      assert {:ok, %{"id" => 1}} =
               Capabilities.create_release("owner", "repo", %{"tag_name" => "v1"}, root)

      assert {:ok, %{"id" => 1}} = Capabilities.get_latest_release("owner", "repo", root)

      assert {:ok, %{"id" => 1}} =
               Capabilities.get_release_by_tag("owner", "repo", "v1.0.0", root)

      assert {:ok, %{"name" => "v1"}} =
               Capabilities.generate_release_notes("owner", "repo", %{"tag_name" => "v1"}, root)
    end

    test "read a branch, compare refs, and delete a ref" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/branches/main"
        Req.Test.json(conn, %{"name" => "main"})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/compare/main...feat"
        Req.Test.json(conn, %{"status" => "ahead"})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/repos/owner/repo/git/refs/heads/feat"
        Plug.Conn.send_resp(conn, 204, "")
      end)

      assert {:ok, %{"name" => "main"}} = Capabilities.get_branch("owner", "repo", "main", root)

      assert {:ok, %{"status" => "ahead"}} =
               Capabilities.compare("owner", "repo", "main", "feat", root)

      assert {:ok, nil} = Capabilities.delete_ref("owner", "repo", "feat", root)
    end
  end

  describe "graphql/3" do
    test "posts the query and gives the data" do
      root = write_config!(~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/graphql"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = JSON.decode!(body)
        assert payload["query"] =~ "viewer"
        assert payload["variables"] == %{"id" => "PR_1"}

        Req.Test.json(conn, %{"data" => %{"viewer" => %{"login" => "octocat"}}})
      end)

      assert Capabilities.graphql("query { viewer { login } }", %{id: "PR_1"}, root) ==
               {:ok, %{"viewer" => %{"login" => "octocat"}}}
    end
  end

  describe "head_sha/3" do
    test "reads the commit that HEAD points at" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      expected = Repository.git!(["-C", repository.root, "rev-parse", "HEAD"]) |> String.trim()

      assert Capabilities.head_sha(repository.root, "checks", :working_directory) ==
               {:ok, expected}

      assert String.length(expected) == 40
    end
  end

  describe "resolve_pull/4" do
    test "reads the open pull request of the current branch without a number" do
      repository = repository_with_origin!("git@github.com:owner/repo.git")
      write_config!(repository.root, ~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls"

        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["head"] == "owner:main"
        assert conn.query_params["state"] == "open"

        Req.Test.json(conn, [%{"number" => 7, "html_url" => "u"}])
      end)

      assert {:ok, target} = Capabilities.resolve_pull(nil, repository.root, "merge_pr", :number)
      assert target.number == 7
      assert target.pull["html_url"] == "u"
      assert target.repo == %{owner: "owner", repo: "repo", branch: "main"}
    end

    test "reads the numbered pull request with a number" do
      repository = repository_with_origin!("git@github.com:owner/repo.git")
      write_config!(repository.root, ~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/owner/repo/pulls/9"

        Req.Test.json(conn, %{"number" => 9})
      end)

      assert {:ok, %{number: 9, pull: %{"number" => 9}}} =
               Capabilities.resolve_pull(9, repository.root, "merge_pr", :number)
    end

    test "reports a branch without an open pull request" do
      repository = repository_with_origin!("git@github.com:owner/repo.git")
      write_config!(repository.root, ~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, []) end)

      assert {:error, %Error{} = error} =
               Capabilities.resolve_pull(nil, repository.root, "merge_pr", :number)

      assert error.type == :github_pull_request_not_found
      assert error.metadata[:number] == nil
      assert error.metadata[:head] == "owner:main"
      assert error.metadata[:field_name] == :number
    end

    test "reports a number that names no pull request" do
      repository = repository_with_origin!("git@github.com:owner/repo.git")
      write_config!(repository.root, ~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      assert {:error, %Error{} = error} =
               Capabilities.resolve_pull(99, repository.root, "merge_pr", :number)

      assert error.type == :github_pull_request_not_found
      assert error.metadata[:number] == 99
      assert error.metadata[:head] == nil
    end

    test "reports another rejected request with its status" do
      repository = repository_with_origin!("git@github.com:owner/repo.git")
      write_config!(repository.root, ~s({"access_token":"token"}))

      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "Bad credentials"})
      end)

      assert {:error, %Error{} = error} =
               Capabilities.resolve_pull(nil, repository.root, "merge_pr", :number)

      assert error.type == :github_request_failed
      assert error.reason == "Bad credentials"
      assert error.metadata[:status] == 401
    end

    test "reports an origin that is not GitHub without calling GitHub" do
      repository = repository_with_origin!("git@gitlab.com:owner/repo.git")

      assert {:error, %Error{type: :github_origin_not_parsed}} =
               Capabilities.resolve_pull(nil, repository.root, "merge_pr", :number)
    end
  end

  @spec write_config!(root :: String.t(), contents :: String.t()) :: :ok
  defp write_config!(root, contents) do
    path = Path.join(root, Capabilities.config_relative_path())
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
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
