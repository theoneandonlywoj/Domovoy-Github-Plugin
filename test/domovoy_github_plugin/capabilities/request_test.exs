defmodule DomovoyGithubPlugin.Capabilities.RequestTest do
  use ExUnit.Case

  import DomovoyGithubPlugin.Test.Github, only: [stub_requests: 1]

  alias DomovoyGithubPlugin.Capabilities
  alias DomovoyGithubPlugin.Capabilities.Request
  alias DomovoyGithubPlugin.Test.Github

  doctest Request

  setup :stub_requests

  setup do
    root = Path.join(System.tmp_dir!(), "domovoy-github-#{System.unique_integer([:positive])}")
    Github.write_config!(root, ~s({"access_token":"token"}))
    on_exit(fn -> File.rm_rf(root) end)

    {:ok, root: root}
  end

  describe "request/4" do
    test "sends the headers of the REST API and decodes a JSON body", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token"]
        assert Plug.Conn.get_req_header(conn, "accept") == ["application/vnd.github+json"]
        assert Plug.Conn.get_req_header(conn, "x-github-api-version") == ["2022-11-28"]

        Req.Test.json(conn, %{"ok" => true})
      end)

      assert Request.request(:get, "/user", [], root) == {:ok, %{"ok" => true}}
    end

    test "gives nil for an empty body", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 204, "") end)

      assert Request.request(:delete, "/repos/o/r/git/refs/heads/b", [], root) == {:ok, nil}
    end

    test "reports the status and the message of a rejected request", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "Bad credentials"})
      end)

      assert Request.request(:get, "/user", [], root) ==
               {:error, %{status: 401, message: "Bad credentials"}}
    end

    test "appends the errors of a validation failure", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{
          "message" => "Validation Failed",
          "errors" => [
            %{"message" => "A pull request already exists"},
            %{"resource" => "PullRequest", "field" => "base", "code" => "invalid"}
          ]
        })
      end)

      assert Request.request(:post, "/repos/o/r/pulls", [json: %{}], root) ==
               {:error,
                %{
                  status: 422,
                  message:
                    "Validation Failed; A pull request already exists; PullRequest.base invalid"
                }}
    end

    test "describes a rejected request without a body by its status", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 502, "") end)

      assert Request.request(:get, "/user", [], root) ==
               {:error, %{status: 502, message: "GitHub API responded with status 502"}}
    end

    test "reports a transport failure without a status", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, %{status: nil, message: message}} = Request.request(:get, "/user", [], root)
      assert message =~ "GitHub API request failed"
    end

    test "explains a missing access token without calling GitHub" do
      root = Path.join(System.tmp_dir!(), "domovoy-github-#{System.unique_integer([:positive])}")
      Github.write_config!(root, ~s({}))
      on_exit(fn -> File.rm_rf(root) end)

      assert {:error, %{status: nil, message: message}} = Request.request(:get, "/user", [], root)
      assert message =~ "access_token is not set"
      assert message =~ Capabilities.config_relative_path()
    end
  end

  describe "list/4" do
    test "asks for 100 items and follows the next link", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.request_path == "/repos/o/r/pulls"
        assert conn.query_params["per_page"] == "100"
        assert conn.query_params["state"] == "open"

        conn
        |> Plug.Conn.put_resp_header(
          "link",
          ~s(<https://api.github.com/repos/o/r/pulls?state=open&per_page=100&page=2>; rel="next")
        )
        |> Req.Test.json([%{"number" => 1}])
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["page"] == "2"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token"]

        Req.Test.json(conn, [%{"number" => 2}])
      end)

      assert Request.list("/repos/o/r/pulls", [state: "open"], root) ==
               {:ok, [%{"number" => 1}, %{"number" => 2}]}
    end

    test "unwraps a list that sits under a key", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"total_count" => 1, "check_runs" => [%{"name" => "ci"}]})
      end)

      assert Request.list("/repos/o/r/commits/abc/check-runs", [], root, into: "check_runs") ==
               {:ok, [%{"name" => "ci"}]}
    end

    test "stops at max_pages", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("link", ~s(<https://api.github.com/x?page=2>; rel="next"))
        |> Req.Test.json([1])
      end)

      assert Request.list("/x", [], root, max_pages: 1) == {:ok, [1]}
    end

    test "reports a body that is not a list", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, %{"message" => "hi"}) end)

      assert {:error, %{status: nil, message: message}} = Request.list("/x", [], root)
      assert message =~ "gave no list"
    end

    test "reports a rejected request", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "Forbidden"})
      end)

      assert Request.list("/x", [], root) == {:error, %{status: 403, message: "Forbidden"}}
    end
  end

  describe "download/2" do
    test "follows the redirect and gives the raw bytes, without the token", %{root: root} do
      zip = <<80, 75, 3, 4, 0, 0>>

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/repos/o/r/actions/runs/1/logs"

        conn
        |> Plug.Conn.put_resp_header("location", "https://objects.example.com/logs.zip")
        |> Plug.Conn.send_resp(302, "")
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.host == "objects.example.com"
        assert Plug.Conn.get_req_header(conn, "authorization") == []

        conn
        |> Plug.Conn.put_resp_content_type("application/zip")
        |> Plug.Conn.send_resp(200, zip)
      end)

      assert Request.download("/repos/o/r/actions/runs/1/logs", root) == {:ok, zip}
    end

    test "reports a rejected download", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      assert Request.download("/repos/o/r/actions/runs/1/logs", root) ==
               {:error, %{status: 404, message: "Not Found"}}
    end
  end

  describe "graphql/3" do
    test "gives the data of a successful query", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/graphql"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(body) == %{"query" => "query { x }", "variables" => %{"a" => 1}}

        Req.Test.json(conn, %{"data" => %{"x" => 1}})
      end)

      assert Request.graphql("query { x }", %{a: 1}, root) == {:ok, %{"x" => 1}}
    end

    test "reports the errors of a query that GitHub rejected with 200", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{
          "data" => nil,
          "errors" => [%{"message" => "Could not resolve"}, %{"message" => "Field missing"}]
        })
      end)

      assert Request.graphql("query { x }", %{}, root) ==
               {:error, %{status: 200, message: "Could not resolve; Field missing"}}
    end

    test "reports an HTTP failure", %{root: root} do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(502) |> Req.Test.json(%{"message" => "Bad gateway"})
      end)

      assert Request.graphql("query { x }", %{}, root) ==
               {:error, %{status: 502, message: "Bad gateway"}}
    end
  end
end
