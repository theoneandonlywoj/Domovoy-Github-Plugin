defmodule DomovoyGithubPlugin.Capabilities do
  @moduledoc """
  The GitHub capabilities that the pull-request workflows of Domovoy reuse.

  Each request goes through `Req` to the REST API of GitHub. The credentials and
  the timeouts come from `.domovoy/config/github.json`. These capabilities find
  that file when they move up from a working directory. Therefore a linked
  worktree gets the configuration of the repository.

  These capabilities read the repository of a request from the `origin` remote
  of the local checkout. The repository is not in the configuration. Therefore
  they act on the repository of the working directory of the node.

  A capability that resolves the repository or the pull request of a checkout
  returns `{:error, %DomovoyCore.Error{}}`. A capability that calls GitHub
  returns `{:error, failure}`, where the failure holds the HTTP status and the
  message of GitHub. Therefore a runner tells a missing resource apart from a
  rejected request. `DomovoyGithubPlugin.Capabilities.Request` sends every
  request.

  ## Examples

      iex> DomovoyGithubPlugin.Capabilities.config_relative_path()
      ".domovoy/config/github.json"
  """

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyGithubPlugin.Capabilities.Request
  alias DomovoyGithubPlugin.Error, as: GithubError

  alias DomovoyGitPlugin.Capabilities, as: GitCapabilities

  @typedoc "The repository and branch a GitHub request acts on."
  @type repo() :: %{owner: String.t(), repo: String.t(), branch: String.t()}

  @typedoc "Why a request failed: the HTTP status and the message of GitHub."
  @type failure() :: Request.failure()

  @typedoc "A successful API call's decoded body, or a failure."
  @type result() :: Request.result()

  @typedoc "The repository and the pull request that a request acts on."
  @type target() :: %{repo: repo(), number: pos_integer(), pull: map()}

  @config_file "github.json"
  @config_directory [".domovoy", "config"]
  @default_connect_timeout_ms 15_000
  @default_receive_timeout_ms 60_000

  @origin_pattern ~r{^(?:git@github\.com:|https://github\.com/)(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$}

  @doc """
  Returns the name of the GitHub configuration file.

  The capabilities use this name. Therefore the repository states the name of
  the file only once.

  ## Examples

      iex> DomovoyGithubPlugin.Capabilities.config_file()
      "github.json"

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec config_file() :: String.t()
  def config_file, do: @config_file

  @doc """
  Returns the relative path of Domovoy's GitHub configuration file.

  This function does not check whether the file exists.

  ## Examples

      iex> DomovoyGithubPlugin.Capabilities.config_relative_path()
      ".domovoy/config/github.json"
  """
  @spec config_relative_path() :: String.t()
  def config_relative_path, do: Path.join(@config_directory ++ [@config_file])

  @doc """
  Finds the GitHub configuration path for a starting directory.

  Checks `directory` and each ancestor, returning the first regular
  `.domovoy/config/github.json` found, or the candidate path beneath the
  original directory when none exists.

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec find_config_path(String.t()) :: String.t()
  def find_config_path(directory) when is_binary(directory),
    do: find_path(directory, directory, config_relative_path())

  @doc """
  Loads and decodes a GitHub configuration file.

  This function gives `:error` if it cannot read or decode the file.

  ## Examples

  This function reads the disk, so this example is illustrative.

      iex> DomovoyGithubPlugin.Capabilities.load_config("/repo/.domovoy/config/github.json")
      {:ok, %{"access_token" => "ghp_example", "default_base_branch" => "main"}}
  """
  @spec load_config(path :: String.t()) :: {:ok, map()} | :error
  def load_config(path) when is_binary(path), do: decode(path)

  @typedoc "A GitHub configuration: the path of the file, or its decoded map."
  @type config() :: String.t() | map()

  @doc """
  Reads `"access_token"` from a GitHub configuration.

  `config` is the path of the file, or the map that `load_config/1` gave.
  A caller that reads more than one field passes the map. Therefore the file
  is read once.

  Returns `:error` when the file cannot be read or the field is absent or blank.

  ## Examples

      iex> DomovoyGithubPlugin.Capabilities.access_token(%{"access_token" => " ghp_x "})
      {:ok, "ghp_x"}

      iex> DomovoyGithubPlugin.Capabilities.access_token(%{"access_token" => ""})
      :error

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec access_token(config()) :: {:ok, String.t()} | :error
  def access_token(config), do: read_field(config, "access_token")

  @doc """
  Reads `"default_base_branch"` from a GitHub configuration.

  This is the branch a pull request targets when a caller does not name one.
  `config` is the path of the file, or the map that `load_config/1` gave.

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec default_base_branch(config()) :: {:ok, String.t()} | :error
  def default_base_branch(config), do: read_field(config, "default_base_branch")

  @doc """
  Reads the connect timeout in milliseconds, falling back to
  `#{@default_connect_timeout_ms}` when unset or invalid.

  `config` is the path of the file, or the map that `load_config/1` gave.

  ## Examples

      iex> DomovoyGithubPlugin.Capabilities.connect_timeout_ms(%{"connect_timeout_ms" => 500})
      500

      iex> DomovoyGithubPlugin.Capabilities.connect_timeout_ms(%{"connect_timeout_ms" => 0})
      15000

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec connect_timeout_ms(config()) :: pos_integer()
  def connect_timeout_ms(config) do
    case read_integer_field(config, "connect_timeout_ms") do
      {:ok, value} -> value
      :error -> @default_connect_timeout_ms
    end
  end

  @doc """
  Reads the receive timeout in milliseconds, falling back to
  `#{@default_receive_timeout_ms}` when unset or invalid.

  `config` is the path of the file, or the map that `load_config/1` gave.

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec receive_timeout_ms(config()) :: pos_integer()
  def receive_timeout_ms(config) do
    case read_integer_field(config, "receive_timeout_ms") do
      {:ok, value} -> value
      :error -> @default_receive_timeout_ms
    end
  end

  @doc """
  Resolves the GitHub owner, repository, and current branch for a local checkout.

  The owner and repository come from the `origin` remote, in either its SSH or
  its HTTPS form. A remote pointing somewhere other than GitHub returns a
  contextual `DomovoyCore.Error` rather than a guess.

  ## Equivalent Bash

      git -C /repo remote get-url origin
      git -C /repo rev-parse --abbrev-ref HEAD
  """
  @spec current_repo(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: atom()
        ) :: {:ok, repo()} | {:error, Error.t()}
  def current_repo(working_directory, node_name, field_name) when is_binary(working_directory) do
    with {:ok, output} <-
           GitCapabilities.run_command(
             ["remote", "get-url", "origin"],
             working_directory,
             node_name,
             field_name
           ),
         {:ok, owner, repo} <- output |> String.trim() |> parse_origin(node_name, field_name),
         {:ok, branch} <-
           GitCapabilities.current_branch_abbrev(working_directory, node_name, field_name) do
      {:ok, %{owner: owner, repo: repo, branch: branch}}
    end
  end

  @doc """
  Lists the open pull requests whose head is `head`, written as `owner:branch`.

  Returns `{:ok, []}` when the branch has no open pull request, which is a
  successful answer rather than a failure.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/pulls?head=<owner>:<branch>&state=open"
  """
  @spec list_open_pulls(
          owner :: String.t(),
          repo :: String.t(),
          head :: String.t(),
          working_directory :: String.t()
        ) :: result()
  def list_open_pulls(owner, repo, head, working_directory),
    do: list_pulls(owner, repo, head, "open", working_directory)

  @doc """
  Lists the pull requests whose head is `head`, written as `owner:branch`.

  `state` selects the pull requests. It is `"open"`, `"closed"`, or `"all"`.
  `list_open_pulls/4` is the shorter form for the open ones.

  The newest pull request comes first. The request names `sort` and `direction`.
  Therefore the order does not depend on the defaults of GitHub. A branch that
  carried more than one pull request reports its most recent one.

  Returns `{:ok, []}` when the branch has no pull request in that state. This is
  a successful answer and not a failure.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/pulls?head=<owner>:<branch>&state=all&sort=created&direction=desc"
  """
  @spec list_pulls(
          owner :: String.t(),
          repo :: String.t(),
          head :: String.t(),
          state :: String.t(),
          working_directory :: String.t()
        ) :: result()
  def list_pulls(owner, repo, head, state, working_directory)
      when is_binary(owner) and is_binary(repo) and is_binary(head) and is_binary(state) do
    Request.request(
      :get,
      "/repos/#{owner}/#{repo}/pulls",
      [params: [head: head, state: state, sort: "created", direction: "desc"]],
      working_directory
    )
  end

  @doc """
  Creates a pull request from `body`, which carries `title`, `body`, `head`, and
  `base`.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/pulls" --input body.json
  """
  @spec create_pull(String.t(), String.t(), map(), String.t()) :: result()
  def create_pull(owner, repo, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_map(body) do
    Request.request(:post, "/repos/#{owner}/#{repo}/pulls", [json: body], working_directory)
  end

  @doc """
  Updates pull request `number` from `body`, which carries the fields to change.

  ## Equivalent Bash

      gh api --method PATCH "repos/<owner>/<repo>/pulls/<number>" --input body.json
  """
  @spec update_pull(String.t(), String.t(), integer(), map(), String.t()) :: result()
  def update_pull(owner, repo, number, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_map(body) do
    Request.request(
      :patch,
      "/repos/#{owner}/#{repo}/pulls/#{number}",
      [json: body],
      working_directory
    )
  end

  @doc """
  Reads the repository, with its `default_branch`.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>"
  """
  @spec get_repository(String.t(), String.t(), String.t()) :: result()
  def get_repository(owner, repo, working_directory) when is_binary(owner) and is_binary(repo),
    do: Request.request(:get, "/repos/#{owner}/#{repo}", [], working_directory)

  @doc """
  Lists the pull requests whose base branch is `base`, newest first.

  `state` is `"open"`, `"closed"`, or `"all"`. A stacked pull request has its
  parent branch as `base`. Therefore this lists the children of a branch.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/pulls?base=<base>&state=open&sort=created&direction=desc"
  """
  @spec list_pulls_by_base(String.t(), String.t(), String.t(), String.t(), String.t()) :: result()
  def list_pulls_by_base(owner, repo, base, state, working_directory)
      when is_binary(owner) and is_binary(repo) and is_binary(base) and is_binary(state) do
    Request.request(
      :get,
      "/repos/#{owner}/#{repo}/pulls",
      [params: [base: base, state: state, sort: "created", direction: "desc"]],
      working_directory
    )
  end

  @doc """
  Opens a pull request for `head_branch`, or changes the open one.

  A branch without an open pull request gets one from `create_body`, which
  carries `title`, `body`, `head`, `base`, and `draft`. A branch with an open
  pull request gets `update_body` applied to the newest one. The answer says
  which happened and holds the pull request.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/pulls?head=<owner>:<branch>&state=open"
      gh api --method POST "repos/<owner>/<repo>/pulls" --input create.json
      gh api --method PATCH "repos/<owner>/<repo>/pulls/<number>" --input update.json
  """
  @spec upsert_pull(
          owner :: String.t(),
          repo :: String.t(),
          head_branch :: String.t(),
          create_body :: map(),
          update_body :: map(),
          working_directory :: String.t()
        ) :: {:ok, {:created | :updated, map()}} | {:error, failure()}
  def upsert_pull(owner, repo, head_branch, create_body, update_body, working_directory)
      when is_binary(head_branch) and is_map(create_body) and is_map(update_body) do
    head = "#{owner}:#{head_branch}"

    with {:ok, pulls} <- list_open_pulls(owner, repo, head, working_directory) do
      upsert(pulls, owner, repo, {create_body, update_body}, working_directory)
    end
  end

  @spec upsert(
          pulls :: term(),
          owner :: String.t(),
          repo :: String.t(),
          bodies :: {map(), map()},
          working_directory :: String.t()
        ) :: {:ok, {:created | :updated, map()}} | {:error, failure()}
  defp upsert([], owner, repo, {create_body, _update_body}, working_directory) do
    owner
    |> create_pull(repo, create_body, working_directory)
    |> upserted(:created)
  end

  defp upsert([%{"number" => number} | _rest], owner, repo, {_create, update_body}, directory)
       when is_integer(number) do
    owner
    |> update_pull(repo, number, update_body, directory)
    |> upserted(:updated)
  end

  defp upsert(body, _owner, _repo, _bodies, _working_directory), do: unexpected(body)

  @spec upserted(result :: result(), action :: :created | :updated) ::
          {:ok, {:created | :updated, map()}} | {:error, failure()}
  defp upserted({:ok, pull}, action) when is_map(pull), do: {:ok, {action, pull}}
  defp upserted({:ok, body}, _action), do: unexpected(body)
  defp upserted({:error, failure}, _action), do: {:error, failure}

  @spec unexpected(body :: term()) :: {:error, failure()}
  defp unexpected(body),
    do: {:error, %{status: nil, message: "GitHub API gave an unexpected body: " <> inspect(body)}}

  @doc """
  Reads pull request `number`.

  A number that names no pull request gives a failure with status `404`.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/pulls/<number>"
  """
  @spec get_pull(String.t(), String.t(), pos_integer(), String.t()) :: result()
  def get_pull(owner, repo, number, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) do
    Request.request(:get, "/repos/#{owner}/#{repo}/pulls/#{number}", [], working_directory)
  end

  @doc """
  Merges pull request `number` with `body`, which carries `merge_method` and,
  when the caller names them, `commit_title` and `commit_message`.

  GitHub answers a pull request that it cannot merge with status `405`, and a
  head that moved since the caller read it with status `409`.

  ## Equivalent Bash

      gh api --method PUT "repos/<owner>/<repo>/pulls/<number>/merge" --input body.json
  """
  @spec merge_pull(String.t(), String.t(), pos_integer(), map(), String.t()) :: result()
  def merge_pull(owner, repo, number, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_map(body) do
    Request.request(
      :put,
      "/repos/#{owner}/#{repo}/pulls/#{number}/merge",
      [json: body],
      working_directory
    )
  end

  @doc """
  Asks the people and the teams in `body` to review pull request `number`.

  `body` carries `reviewers`, a list of logins, and `team_reviewers`, a list of
  team slugs. GitHub answers with the pull request.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/pulls/<number>/requested_reviewers" --input body.json
  """
  @spec request_reviewers(String.t(), String.t(), pos_integer(), map(), String.t()) :: result()
  def request_reviewers(owner, repo, number, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_map(body) do
    Request.request(
      :post,
      "/repos/#{owner}/#{repo}/pulls/#{number}/requested_reviewers",
      [json: body],
      working_directory
    )
  end

  @doc """
  Brings the head branch of pull request `number` up to date with its base.

  GitHub starts the update and answers with status `202`. Therefore the answer
  says that the update began and not that it finished.

  ## Equivalent Bash

      gh api --method PUT "repos/<owner>/<repo>/pulls/<number>/update-branch"
  """
  @spec update_pull_branch(String.t(), String.t(), pos_integer(), String.t()) :: result()
  def update_pull_branch(owner, repo, number, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) do
    Request.request(
      :put,
      "/repos/#{owner}/#{repo}/pulls/#{number}/update-branch",
      [json: %{}],
      working_directory
    )
  end

  @doc """
  Lists every file that pull request `number` changes.

  ## Equivalent Bash

      gh api --paginate "repos/<owner>/<repo>/pulls/<number>/files"
  """
  @spec list_pull_files(String.t(), String.t(), pos_integer(), String.t()) ::
          {:ok, [map()]} | {:error, failure()}
  def list_pull_files(owner, repo, number, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) do
    Request.list("/repos/#{owner}/#{repo}/pulls/#{number}/files", [], working_directory)
  end

  @doc """
  Lists every commit of pull request `number`.

  ## Equivalent Bash

      gh api --paginate "repos/<owner>/<repo>/pulls/<number>/commits"
  """
  @spec list_pull_commits(String.t(), String.t(), pos_integer(), String.t()) ::
          {:ok, [map()]} | {:error, failure()}
  def list_pull_commits(owner, repo, number, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) do
    Request.list("/repos/#{owner}/#{repo}/pulls/#{number}/commits", [], working_directory)
  end

  @doc """
  Marks the draft pull request with GraphQL id `node_id` as ready for review.

  The REST API cannot do this. Therefore this capability goes through GraphQL.
  `node_id` is the `node_id` field of a pull request from the REST API.

  ## Equivalent Bash

      gh api graphql -F id=<node_id> -f query='mutation($id: ID!) {
        markPullRequestReadyForReview(input: {pullRequestId: $id}) {
          pullRequest { number isDraft url }
        }
      }'
  """
  @spec mark_pull_ready_for_review(node_id :: String.t(), working_directory :: String.t()) ::
          result()
  def mark_pull_ready_for_review(node_id, working_directory) when is_binary(node_id) do
    query = """
    mutation($id: ID!) {
      markPullRequestReadyForReview(input: {pullRequestId: $id}) {
        pullRequest { number isDraft url }
      }
    }
    """

    Request.graphql(query, %{id: node_id}, working_directory)
  end

  @doc """
  Lists every conversation comment of pull request or issue `number`.

  A conversation comment sits under the description. A review comment sits on
  a line of the diff, and `list_review_threads/4` reads those.

  ## Equivalent Bash

      gh api --paginate "repos/<owner>/<repo>/issues/<number>/comments"
  """
  @spec list_issue_comments(String.t(), String.t(), pos_integer(), String.t()) ::
          {:ok, [map()]} | {:error, failure()}
  def list_issue_comments(owner, repo, number, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) do
    Request.list("/repos/#{owner}/#{repo}/issues/#{number}/comments", [], working_directory)
  end

  @doc """
  Writes a conversation comment with `body` on pull request or issue `number`.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/issues/<number>/comments" -f body=<body>
  """
  @spec create_issue_comment(String.t(), String.t(), pos_integer(), String.t(), String.t()) ::
          result()
  def create_issue_comment(owner, repo, number, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_binary(body) do
    Request.request(
      :post,
      "/repos/#{owner}/#{repo}/issues/#{number}/comments",
      [json: %{"body" => body}],
      working_directory
    )
  end

  @doc """
  Replaces the text of conversation comment `comment_id` with `body`.

  ## Equivalent Bash

      gh api --method PATCH "repos/<owner>/<repo>/issues/comments/<comment_id>" -f body=<body>
  """
  @spec update_issue_comment(String.t(), String.t(), pos_integer(), String.t(), String.t()) ::
          result()
  def update_issue_comment(owner, repo, comment_id, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(comment_id) and is_binary(body) do
    Request.request(
      :patch,
      "/repos/#{owner}/#{repo}/issues/comments/#{comment_id}",
      [json: %{"body" => body}],
      working_directory
    )
  end

  @doc """
  Submits a review of pull request `number` from `body`, which carries
  `event` (`APPROVE`, `REQUEST_CHANGES`, or `COMMENT`) and `body`.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/pulls/<number>/reviews" --input body.json
  """
  @spec create_review(String.t(), String.t(), pos_integer(), map(), String.t()) :: result()
  def create_review(owner, repo, number, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_map(body) do
    Request.request(
      :post,
      "/repos/#{owner}/#{repo}/pulls/#{number}/reviews",
      [json: body],
      working_directory
    )
  end

  @doc """
  Lists every review of pull request `number`, oldest first.

  ## Equivalent Bash

      gh api --paginate "repos/<owner>/<repo>/pulls/<number>/reviews"
  """
  @spec list_reviews(String.t(), String.t(), pos_integer(), String.t()) ::
          {:ok, [map()]} | {:error, failure()}
  def list_reviews(owner, repo, number, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) do
    Request.list("/repos/#{owner}/#{repo}/pulls/#{number}/reviews", [], working_directory)
  end

  @doc """
  Writes a comment on a line of the diff of pull request `number`.

  `body` carries `body`, `commit_id`, `path`, `line`, and `side`.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/pulls/<number>/comments" --input body.json
  """
  @spec create_review_comment(String.t(), String.t(), pos_integer(), map(), String.t()) ::
          result()
  def create_review_comment(owner, repo, number, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_map(body) do
    Request.request(
      :post,
      "/repos/#{owner}/#{repo}/pulls/#{number}/comments",
      [json: body],
      working_directory
    )
  end

  @doc """
  Replies to review comment `comment_id` of pull request `number` with `body`.

  The reply joins the thread of that comment.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/pulls/<number>/comments/<comment_id>/replies" -f body=<body>
  """
  @spec reply_to_review_comment(
          owner :: String.t(),
          repo :: String.t(),
          number :: pos_integer(),
          comment_id :: pos_integer(),
          body :: String.t(),
          working_directory :: String.t()
        ) :: result()
  def reply_to_review_comment(owner, repo, number, comment_id, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and
             is_integer(comment_id) and is_binary(body) do
    Request.request(
      :post,
      "/repos/#{owner}/#{repo}/pulls/#{number}/comments/#{comment_id}/replies",
      [json: %{"body" => body}],
      working_directory
    )
  end

  @doc """
  Lists the review threads of pull request `number` with their first comment.

  The REST API does not report whether a thread is resolved. Therefore this
  capability goes through GraphQL. It reads the first 100 threads.

  ## Equivalent Bash

      gh api graphql -F owner=<owner> -F repo=<repo> -F number=<number> -f query='
        query($owner: String!, $repo: String!, $number: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $number) {
              reviewThreads(first: 100) {
                nodes {
                  id isResolved isOutdated path line
                  comments(first: 1) { nodes { databaseId body author { login } } }
                }
              }
            }
          }
        }'
  """
  @spec list_review_threads(String.t(), String.t(), pos_integer(), String.t()) :: result()
  def list_review_threads(owner, repo, number, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) do
    query = """
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            nodes {
              id isResolved isOutdated path line
              comments(first: 1) { nodes { databaseId body author { login } } }
            }
          }
        }
      }
    }
    """

    Request.graphql(query, %{owner: owner, repo: repo, number: number}, working_directory)
  end

  @doc """
  Marks review thread `thread_id` as resolved.

  `thread_id` is the GraphQL id of a thread from `list_review_threads/4`.

  ## Equivalent Bash

      gh api graphql -F id=<thread_id> -f query='mutation($id: ID!) {
        resolveReviewThread(input: {threadId: $id}) { thread { id isResolved } }
      }'
  """
  @spec resolve_review_thread(thread_id :: String.t(), working_directory :: String.t()) ::
          result()
  def resolve_review_thread(thread_id, working_directory) when is_binary(thread_id) do
    query = """
    mutation($id: ID!) {
      resolveReviewThread(input: {threadId: $id}) { thread { id isResolved } }
    }
    """

    Request.graphql(query, %{id: thread_id}, working_directory)
  end

  @doc """
  Lists every check run of commit `sha`.

  A check run comes from GitHub Actions or an app. A commit status comes from
  the older status API, and `get_combined_status/4` reads those.

  ## Equivalent Bash

      gh api --paginate "repos/<owner>/<repo>/commits/<sha>/check-runs" --jq .check_runs
  """
  @spec list_check_runs(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, [map()]} | {:error, failure()}
  def list_check_runs(owner, repo, sha, working_directory)
      when is_binary(owner) and is_binary(repo) and is_binary(sha) do
    Request.list(
      "/repos/#{owner}/#{repo}/commits/#{sha}/check-runs",
      [],
      working_directory,
      into: "check_runs"
    )
  end

  @doc """
  Reads the combined commit status of commit `sha`.

  The answer holds `state` (`"pending"`, `"success"`, or `"failure"`) and the
  list of `statuses`.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/commits/<sha>/status"
  """
  @spec get_combined_status(String.t(), String.t(), String.t(), String.t()) :: result()
  def get_combined_status(owner, repo, sha, working_directory)
      when is_binary(owner) and is_binary(repo) and is_binary(sha) do
    Request.request(:get, "/repos/#{owner}/#{repo}/commits/#{sha}/status", [], working_directory)
  end

  @doc """
  Sets a commit status on commit `sha` from `body`, which carries `state`,
  `context`, and optional `description` and `target_url`.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/statuses/<sha>" --input body.json
  """
  @spec create_commit_status(String.t(), String.t(), String.t(), map(), String.t()) :: result()
  def create_commit_status(owner, repo, sha, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_binary(sha) and is_map(body) do
    Request.request(
      :post,
      "/repos/#{owner}/#{repo}/statuses/#{sha}",
      [json: body],
      working_directory
    )
  end

  @doc """
  Lists the workflow runs that `params` select, newest first.

  `workflow` is the file name or the id of a workflow, or `nil` for every
  workflow. `params` are the filters of GitHub, such as `branch:`, `event:`,
  `status:`, and `per_page:`. This reads one page. Therefore pass
  `per_page: 1` for the newest run.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/actions/workflows/<workflow>/runs?branch=<branch>&per_page=1" --jq .workflow_runs
  """
  @spec list_workflow_runs(
          owner :: String.t(),
          repo :: String.t(),
          workflow :: String.t() | nil,
          params :: keyword(),
          working_directory :: String.t()
        ) :: {:ok, [map()]} | {:error, failure()}
  def list_workflow_runs(owner, repo, workflow, params, working_directory)
      when is_binary(owner) and is_binary(repo) and (is_binary(workflow) or is_nil(workflow)) and
             is_list(params) do
    path =
      case workflow do
        nil -> "/repos/#{owner}/#{repo}/actions/runs"
        workflow -> "/repos/#{owner}/#{repo}/actions/workflows/#{workflow}/runs"
      end

    with {:ok, body} <- Request.request(:get, path, [params: params], working_directory) do
      unwrap(body, "workflow_runs")
    end
  end

  @doc """
  Reads workflow run `run_id`.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/actions/runs/<run_id>"
  """
  @spec get_workflow_run(String.t(), String.t(), pos_integer(), String.t()) :: result()
  def get_workflow_run(owner, repo, run_id, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(run_id) do
    Request.request(:get, "/repos/#{owner}/#{repo}/actions/runs/#{run_id}", [], working_directory)
  end

  @doc """
  Starts `workflow` on `ref` with `inputs`.

  `workflow` is the file name, such as `ci.yml`, or the id. The workflow must
  have a `workflow_dispatch` trigger. GitHub answers with `204` and does not
  name the run. Therefore a caller that needs the run reads the newest one
  with `list_workflow_runs/5` after a moment.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/actions/workflows/<workflow>/dispatches" -f ref=<ref>
  """
  @spec dispatch_workflow(
          owner :: String.t(),
          repo :: String.t(),
          workflow :: String.t(),
          ref :: String.t(),
          inputs :: map(),
          working_directory :: String.t()
        ) :: result()
  def dispatch_workflow(owner, repo, workflow, ref, inputs, working_directory)
      when is_binary(owner) and is_binary(repo) and is_binary(workflow) and is_binary(ref) and
             is_map(inputs) do
    Request.request(
      :post,
      "/repos/#{owner}/#{repo}/actions/workflows/#{workflow}/dispatches",
      [json: %{"ref" => ref, "inputs" => inputs}],
      working_directory
    )
  end

  @doc """
  Lists every job of workflow run `run_id`, with the steps of each.

  ## Equivalent Bash

      gh api --paginate "repos/<owner>/<repo>/actions/runs/<run_id>/jobs" --jq .jobs
  """
  @spec list_workflow_jobs(String.t(), String.t(), pos_integer(), String.t()) ::
          {:ok, [map()]} | {:error, failure()}
  def list_workflow_jobs(owner, repo, run_id, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(run_id) do
    Request.list(
      "/repos/#{owner}/#{repo}/actions/runs/#{run_id}/jobs",
      [],
      working_directory,
      into: "jobs"
    )
  end

  @doc """
  Downloads the logs of workflow run `run_id` as a zip archive.

  GitHub keeps the logs of a run that finished. A run that is still going
  gives a failure.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/actions/runs/<run_id>/logs" > logs.zip
  """
  @spec download_workflow_run_logs(String.t(), String.t(), pos_integer(), String.t()) ::
          {:ok, binary()} | {:error, failure()}
  def download_workflow_run_logs(owner, repo, run_id, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(run_id) do
    Request.download("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/logs", working_directory)
  end

  @spec unwrap(body :: term(), key :: String.t()) :: {:ok, [map()]} | {:error, failure()}
  defp unwrap(%{} = body, key) do
    case Map.fetch(body, key) do
      {:ok, items} when is_list(items) -> {:ok, items}
      _other -> unexpected(body)
    end
  end

  defp unwrap(body, _key), do: unexpected(body)

  @doc """
  Adds `labels` to pull request or issue `number`, keeping the ones it has.

  GitHub makes a label that the repository does not have. The answer lists
  every label of the pull request or issue.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/issues/<number>/labels" --input body.json
  """
  @spec add_labels(String.t(), String.t(), pos_integer(), [String.t()], String.t()) :: result()
  def add_labels(owner, repo, number, labels, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_list(labels) do
    Request.request(
      :post,
      "/repos/#{owner}/#{repo}/issues/#{number}/labels",
      [json: %{"labels" => labels}],
      working_directory
    )
  end

  @doc """
  Replaces every label of pull request or issue `number` with `labels`.

  An empty list removes every label. The answer lists the labels that remain.

  ## Equivalent Bash

      gh api --method PUT "repos/<owner>/<repo>/issues/<number>/labels" --input body.json
  """
  @spec set_labels(String.t(), String.t(), pos_integer(), [String.t()], String.t()) :: result()
  def set_labels(owner, repo, number, labels, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_list(labels) do
    Request.request(
      :put,
      "/repos/#{owner}/#{repo}/issues/#{number}/labels",
      [json: %{"labels" => labels}],
      working_directory
    )
  end

  @doc """
  Removes `label` from pull request or issue `number`.

  A label that the pull request or issue does not have gives a failure with
  status `404`. The answer lists the labels that remain.

  ## Equivalent Bash

      gh api --method DELETE "repos/<owner>/<repo>/issues/<number>/labels/<label>"
  """
  @spec remove_label(String.t(), String.t(), pos_integer(), String.t(), String.t()) :: result()
  def remove_label(owner, repo, number, label, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_binary(label) do
    Request.request(
      :delete,
      "/repos/#{owner}/#{repo}/issues/#{number}/labels/#{encode(label)}",
      [],
      working_directory
    )
  end

  @doc """
  Assigns `assignees`, a list of logins, to pull request or issue `number`,
  keeping the ones it has.

  GitHub ignores a login that cannot be assigned and does not report a
  failure. The answer is the pull request or issue with its `assignees`.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/issues/<number>/assignees" --input body.json
  """
  @spec add_assignees(String.t(), String.t(), pos_integer(), [String.t()], String.t()) :: result()
  def add_assignees(owner, repo, number, assignees, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_list(assignees) do
    Request.request(
      :post,
      "/repos/#{owner}/#{repo}/issues/#{number}/assignees",
      [json: %{"assignees" => assignees}],
      working_directory
    )
  end

  @doc """
  Opens an issue from `body`, which carries `title` and optional `body`,
  `labels`, and `assignees`.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/issues" --input body.json
  """
  @spec create_issue(String.t(), String.t(), map(), String.t()) :: result()
  def create_issue(owner, repo, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_map(body) do
    Request.request(:post, "/repos/#{owner}/#{repo}/issues", [json: body], working_directory)
  end

  @doc """
  Reads issue `number`.

  GitHub answers this for a pull request too, since a pull request is an
  issue. A number that names nothing gives a failure with status `404`.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/issues/<number>"
  """
  @spec get_issue(String.t(), String.t(), pos_integer(), String.t()) :: result()
  def get_issue(owner, repo, number, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) do
    Request.request(:get, "/repos/#{owner}/#{repo}/issues/#{number}", [], working_directory)
  end

  @doc """
  Changes issue `number` from `body`, which carries the fields to change:
  `title`, `body`, `state`, `labels`, or `assignees`.

  ## Equivalent Bash

      gh api --method PATCH "repos/<owner>/<repo>/issues/<number>" --input body.json
  """
  @spec update_issue(String.t(), String.t(), pos_integer(), map(), String.t()) :: result()
  def update_issue(owner, repo, number, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_map(body) do
    Request.request(
      :patch,
      "/repos/#{owner}/#{repo}/issues/#{number}",
      [json: body],
      working_directory
    )
  end

  @doc """
  Makes a release from `body`, which carries `tag_name` and optional `name`,
  `body`, `draft`, `prerelease`, `target_commitish`, and
  `generate_release_notes`.

  GitHub makes the tag when it does not exist, at `target_commitish` or the
  default branch.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/releases" --input body.json
  """
  @spec create_release(String.t(), String.t(), map(), String.t()) :: result()
  def create_release(owner, repo, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_map(body) do
    Request.request(:post, "/repos/#{owner}/#{repo}/releases", [json: body], working_directory)
  end

  @doc """
  Reads the latest release that is neither a draft nor a prerelease.

  A repository without a release gives a failure with status `404`.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/releases/latest"
  """
  @spec get_latest_release(String.t(), String.t(), String.t()) :: result()
  def get_latest_release(owner, repo, working_directory)
      when is_binary(owner) and is_binary(repo) do
    Request.request(:get, "/repos/#{owner}/#{repo}/releases/latest", [], working_directory)
  end

  @doc """
  Reads the release of tag `tag`.

  A tag without a release gives a failure with status `404`.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/releases/tags/<tag>"
  """
  @spec get_release_by_tag(String.t(), String.t(), String.t(), String.t()) :: result()
  def get_release_by_tag(owner, repo, tag, working_directory)
      when is_binary(owner) and is_binary(repo) and is_binary(tag) do
    Request.request(
      :get,
      "/repos/#{owner}/#{repo}/releases/tags/#{encode(tag)}",
      [],
      working_directory
    )
  end

  @doc """
  Writes release notes for `body`, which carries `tag_name` and optional
  `target_commitish`, `previous_tag_name`, and `configuration_file_path`.

  GitHub writes the notes from the pull requests since the previous tag. It
  does not make a release. The answer holds `name` and `body`.

  ## Equivalent Bash

      gh api --method POST "repos/<owner>/<repo>/releases/generate-notes" --input body.json
  """
  @spec generate_release_notes(String.t(), String.t(), map(), String.t()) :: result()
  def generate_release_notes(owner, repo, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_map(body) do
    Request.request(
      :post,
      "/repos/#{owner}/#{repo}/releases/generate-notes",
      [json: body],
      working_directory
    )
  end

  @doc """
  Reads branch `branch`, with its head commit and whether it is protected.

  A name that is not a branch gives a failure with status `404`.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/branches/<branch>"
  """
  @spec get_branch(String.t(), String.t(), String.t(), String.t()) :: result()
  def get_branch(owner, repo, branch, working_directory)
      when is_binary(owner) and is_binary(repo) and is_binary(branch) do
    Request.request(
      :get,
      "/repos/#{owner}/#{repo}/branches/#{encode(branch)}",
      [],
      working_directory
    )
  end

  @doc """
  Compares `head` against `base`, each a branch, a tag, or a commit.

  The answer holds `status` (`"ahead"`, `"behind"`, `"identical"`, or
  `"diverged"`), `ahead_by`, `behind_by`, and `total_commits`.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/compare/<base>...<head>"
  """
  @spec compare(String.t(), String.t(), String.t(), String.t(), String.t()) :: result()
  def compare(owner, repo, base, head, working_directory)
      when is_binary(owner) and is_binary(repo) and is_binary(base) and is_binary(head) do
    Request.request(
      :get,
      "/repos/#{owner}/#{repo}/compare/#{encode(base)}...#{encode(head)}",
      [],
      working_directory
    )
  end

  @doc """
  Deletes branch `branch` from GitHub.

  A branch that does not exist gives a failure with status `422` and the
  message `Reference does not exist`.

  ## Equivalent Bash

      gh api --method DELETE "repos/<owner>/<repo>/git/refs/heads/<branch>"
  """
  @spec delete_ref(String.t(), String.t(), String.t(), String.t()) :: result()
  def delete_ref(owner, repo, branch, working_directory)
      when is_binary(owner) and is_binary(repo) and is_binary(branch) do
    Request.request(
      :delete,
      "/repos/#{owner}/#{repo}/git/refs/heads/#{encode(branch)}",
      [],
      working_directory
    )
  end

  @doc """
  Sends `query` with `variables` to the GraphQL API of GitHub and gives its
  `data`.

  A query that GitHub rejects gives a failure with status `200` and the joined
  messages of GitHub.

  ## Equivalent Bash

      gh api graphql -f query='<query>' -F <name>=<value>
  """
  @spec graphql(query :: String.t(), variables :: map(), working_directory :: String.t()) ::
          result()
  def graphql(query, variables, working_directory) when is_binary(query) and is_map(variables),
    do: Request.graphql(query, variables, working_directory)

  @doc """
  Reads the commit that `HEAD` of a local checkout points at.

  ## Equivalent Bash

      git -C /repo rev-parse HEAD
  """
  @spec head_sha(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: atom()
        ) :: {:ok, String.t()} | {:error, Error.t()}
  def head_sha(working_directory, node_name, field_name) when is_binary(working_directory) do
    with {:ok, output} <-
           GitCapabilities.run_command(
             ["rev-parse", "HEAD"],
             working_directory,
             node_name,
             field_name
           ) do
      {:ok, String.trim(output)}
    end
  end

  @doc """
  Resolves the pull request that a runner acts on.

  `number` names the pull request. Without a number, the pull request is the
  open one of the current branch of the checkout. Each runner that changes a
  pull request goes through this function. Therefore each of them reads
  `number` the same way.

  The answer holds the repository, the number, and the pull request as GitHub
  gave it. A runner reads `node_id`, `head`, `base`, or `html_url` from that
  map and does not send a second request.

  A branch without an open pull request, or a number that names none, gives a
  `:github_pull_request_not_found` error.

  ## Equivalent Bash

      gh api "repos/<owner>/<repo>/pulls/<number>"
      gh api "repos/<owner>/<repo>/pulls?head=<owner>:<branch>&state=open"
  """
  @spec resolve_pull(
          number :: pos_integer() | nil,
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: atom()
        ) :: {:ok, target()} | {:error, Error.t()}
  def resolve_pull(number, working_directory, node_name, field_name)
      when (is_integer(number) or is_nil(number)) and is_binary(working_directory) do
    with {:ok, repo} <- current_repo(working_directory, node_name, field_name) do
      target(repo, number, working_directory, node_name, field_name)
    end
  end

  @spec target(
          repo :: repo(),
          number :: pos_integer() | nil,
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: atom()
        ) :: {:ok, target()} | {:error, Error.t()}
  defp target(repo, nil, working_directory, node_name, field_name) do
    head = "#{repo.owner}:#{repo.branch}"

    case list_open_pulls(repo.owner, repo.repo, head, working_directory) do
      {:ok, [pull | _rest]} when is_map(pull) ->
        {:ok, %{repo: repo, number: pull["number"], pull: pull}}

      {:ok, []} ->
        {:error, GithubError.pull_request_not_found(nil, head, node_name, field_name)}

      {:ok, body} ->
        {:error, GithubError.request_failed(inspect(body), node_name, field_name)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, field_name)}
    end
  end

  defp target(repo, number, working_directory, node_name, field_name) do
    case get_pull(repo.owner, repo.repo, number, working_directory) do
      {:ok, pull} when is_map(pull) ->
        {:ok, %{repo: repo, number: number, pull: pull}}

      {:ok, body} ->
        {:error, GithubError.request_failed(inspect(body), node_name, field_name)}

      {:error, %{status: 404}} ->
        {:error, GithubError.pull_request_not_found(number, nil, node_name, field_name)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, field_name)}
    end
  end

  @spec encode(segment :: String.t()) :: String.t()
  defp encode(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  @spec find_path(directory :: String.t(), original :: String.t(), relative_path :: String.t()) ::
          String.t()
  defp find_path(directory, original, relative_path) do
    config_path = Path.join(directory, relative_path)
    parent = Path.dirname(directory)

    cond do
      File.regular?(config_path) -> config_path
      parent == directory -> Path.join(original, relative_path)
      true -> find_path(parent, original, relative_path)
    end
  end

  @spec decode(config_path :: String.t()) :: {:ok, map()} | :error
  defp decode(config_path) do
    with {:ok, contents} <- File.read(config_path),
         {:ok, decoded} when is_map(decoded) <- JSON.decode(contents) do
      {:ok, decoded}
    else
      _other -> :error
    end
  end

  @spec read_field(config :: config(), field :: String.t()) :: {:ok, String.t()} | :error
  defp read_field(%{} = config, field) when is_binary(field) do
    case config do
      %{^field => value} when is_binary(value) -> trimmed(value)
      _other -> :error
    end
  end

  defp read_field(config_path, field) when is_binary(config_path) and is_binary(field) do
    case decode(config_path) do
      {:ok, config} -> read_field(config, field)
      :error -> :error
    end
  end

  @spec trimmed(value :: String.t()) :: {:ok, String.t()} | :error
  defp trimmed(value) do
    case String.trim(value) do
      "" -> :error
      trimmed -> {:ok, trimmed}
    end
  end

  @spec read_integer_field(config :: config(), field :: String.t()) ::
          {:ok, pos_integer()} | :error
  defp read_integer_field(%{} = config, field) when is_binary(field) do
    case config do
      %{^field => value} when is_integer(value) and value > 0 -> {:ok, value}
      _other -> :error
    end
  end

  defp read_integer_field(config_path, field) when is_binary(config_path) and is_binary(field) do
    case decode(config_path) do
      {:ok, config} -> read_integer_field(config, field)
      :error -> :error
    end
  end

  @spec parse_origin(
          remote_url :: String.t(),
          node_name :: Node.name(),
          field_name :: atom()
        ) :: {:ok, String.t(), String.t()} | {:error, Error.t()}
  defp parse_origin(remote_url, node_name, field_name) do
    case Regex.named_captures(@origin_pattern, remote_url) do
      %{"owner" => owner, "repo" => repo} -> {:ok, owner, repo}
      nil -> {:error, GithubError.origin_not_parsed(remote_url, node_name, field_name)}
    end
  end
end
