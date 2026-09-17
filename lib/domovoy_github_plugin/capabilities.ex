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

  A capability that can fail returns `{:error, %DomovoyCore.Error{}}` or the
  documented graph-agnostic error value.

  ## Examples

      iex> DomovoyGithubPlugin.Capabilities.config_relative_path()
      ".domovoy/config/github.json"
  """

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyGithubPlugin.Error, as: GithubError

  alias DomovoyGitPlugin.Capabilities, as: GitCapabilities

  @typedoc "The repository and branch a GitHub request acts on."
  @type repo() :: %{owner: String.t(), repo: String.t(), branch: String.t()}

  @typedoc "A successful API call's decoded body, or a human-readable failure."
  @type result() :: {:ok, term()} | {:error, String.t()}

  @api_base "https://api.github.com"
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

  @doc """
  Reads `"access_token"` from a GitHub configuration file.

  Returns `:error` when the file cannot be read or the field is absent or blank.

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec access_token(String.t()) :: {:ok, String.t()} | :error
  def access_token(config_path), do: read_field(config_path, "access_token")

  @doc """
  Reads `"default_base_branch"` from a GitHub configuration file.

  This is the branch a pull request targets when a caller does not name one.

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec default_base_branch(String.t()) :: {:ok, String.t()} | :error
  def default_base_branch(config_path), do: read_field(config_path, "default_base_branch")

  @doc """
  Reads the connect timeout in milliseconds, falling back to
  `#{@default_connect_timeout_ms}` when unset or invalid.

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec connect_timeout_ms(String.t()) :: pos_integer()
  def connect_timeout_ms(config_path) do
    case read_integer_field(config_path, "connect_timeout_ms") do
      {:ok, value} -> value
      :error -> @default_connect_timeout_ms
    end
  end

  @doc """
  Reads the receive timeout in milliseconds, falling back to
  `#{@default_receive_timeout_ms}` when unset or invalid.

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec receive_timeout_ms(String.t()) :: pos_integer()
  def receive_timeout_ms(config_path) do
    case read_integer_field(config_path, "receive_timeout_ms") do
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
    request(
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
    request(:post, "/repos/#{owner}/#{repo}/pulls", [json: body], working_directory)
  end

  @doc """
  Updates pull request `number` from `body`, which carries the fields to change.

  ## Equivalent Bash

      gh api --method PATCH "repos/<owner>/<repo>/pulls/<number>" --input body.json
  """
  @spec update_pull(String.t(), String.t(), integer(), map(), String.t()) :: result()
  def update_pull(owner, repo, number, body, working_directory)
      when is_binary(owner) and is_binary(repo) and is_integer(number) and is_map(body) do
    request(:patch, "/repos/#{owner}/#{repo}/pulls/#{number}", [json: body], working_directory)
  end

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

  @spec read_field(config_path :: String.t(), field :: String.t()) :: {:ok, String.t()} | :error
  defp read_field(config_path, field) when is_binary(config_path) and is_binary(field) do
    case decode(config_path) do
      {:ok, %{^field => value}} when is_binary(value) -> trimmed(value)
      _other -> :error
    end
  end

  @spec trimmed(value :: String.t()) :: {:ok, String.t()} | :error
  defp trimmed(value) do
    case String.trim(value) do
      "" -> :error
      trimmed -> {:ok, trimmed}
    end
  end

  @spec read_integer_field(config_path :: String.t(), field :: String.t()) ::
          {:ok, pos_integer()} | :error
  defp read_integer_field(config_path, field) when is_binary(config_path) and is_binary(field) do
    case decode(config_path) do
      {:ok, %{^field => value}} when is_integer(value) and value > 0 -> {:ok, value}
      _other -> :error
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

  @spec request(atom(), String.t(), keyword(), String.t()) :: result()
  defp request(method, path, options, working_directory) do
    config_path = find_config_path(working_directory)

    case access_token(config_path) do
      {:ok, token} -> send_request(method, path, options, token, config_path)
      :error -> {:error, missing_access_token_message(config_path)}
    end
  end

  @spec send_request(atom(), String.t(), keyword(), String.t(), String.t()) :: result()
  defp send_request(method, path, options, token, config_path) do
    request_options =
      Keyword.merge(
        [
          method: method,
          url: @api_base <> path,
          headers: [
            {"authorization", "Bearer " <> token},
            {"accept", "application/vnd.github+json"},
            {"x-github-api-version", "2022-11-28"}
          ],
          connect_options: [timeout: connect_timeout_ms(config_path)],
          receive_timeout: receive_timeout_ms(config_path)
        ],
        options
      )

    case Req.request(request_options) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{body: body}} ->
        {:error, error_message(body)}

      {:error, exception} ->
        {:error, "GitHub API request failed: " <> Exception.message(exception)}
    end
  end

  @spec error_message(term()) :: String.t()
  defp error_message(%{"message" => message}) when is_binary(message), do: message
  defp error_message(body), do: inspect(body)

  @spec missing_access_token_message(String.t()) :: String.t()
  defp missing_access_token_message(config_path) do
    "access_token is not set in #{config_path}; create a personal access token in " <>
      "GitHub at https://github.com/settings/tokens, then set access_token in " <>
      config_relative_path() <> "."
  end
end
