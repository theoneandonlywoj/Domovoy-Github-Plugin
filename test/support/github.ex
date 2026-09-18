defmodule DomovoyGithubPlugin.Test.Github do
  @moduledoc """
  Prepares a GitHub-backed test: a stubbed `Req`, a checkout with a GitHub
  `origin`, and a configuration file with an access token.

  ## Examples

  ```elixir
  setup :stub_requests

  setup do
    {:ok, repository: DomovoyGithubPlugin.Test.Github.repository!()}
  end
  ```
  """

  alias DomovoyGithubPlugin.Capabilities
  alias DomovoyGithubPlugin.Test.Repository

  @origin "git@github.com:owner/repo.git"
  @config ~s({"access_token":"token","default_base_branch":"main"})

  @doc """
  Routes every `Req` request of the test to `Req.Test` under the test module,
  and restores the previous options when the test ends.

  Use it as `setup :stub_requests`. Set expectations with
  `Req.Test.expect(__MODULE__, fn conn -> ... end)`.

  This is a test capability and has no Bash equivalent.
  """
  @spec stub_requests(context :: map()) :: :ok
  def stub_requests(%{module: module} = context) do
    previous_options = Req.default_options()
    Req.default_options(plug: {Req.Test, module}, retry: false)
    Req.Test.set_req_test_from_context(context)
    Req.Test.verify_on_exit!()

    ExUnit.Callbacks.on_exit(fn -> Req.default_options(previous_options) end)

    :ok
  end

  @doc """
  Creates a checkout whose `origin` is `git@github.com:owner/repo.git`, writes
  a GitHub configuration with an access token, and removes both when the test
  ends.

  ## Options

    * `:config` - the contents of the configuration file. The default has an
      access token and `default_base_branch` of `main`.

  ## Equivalent Bash

      git -C <root> remote add origin git@github.com:owner/repo.git
  """
  @spec repository!(opts :: keyword()) :: Repository.t()
  def repository!(opts \\ []) do
    repository = Repository.create!(remote?: false)
    Repository.git!(["-C", repository.root, "remote", "add", "origin", @origin])
    write_config!(repository.root, Keyword.get(opts, :config, @config))

    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(repository.parent) end)

    repository
  end

  @doc """
  Writes `contents` as the GitHub configuration file under `root`.

  This is a test capability and has no Bash equivalent.
  """
  @spec write_config!(root :: String.t(), contents :: String.t()) :: :ok
  def write_config!(root, contents) do
    path = Path.join(root, Capabilities.config_relative_path())
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  @doc """
  Builds a pull request as GitHub reports it, with `overrides` on top.

  The pull request has every field that a runner reads: `number`, `state`,
  `merged_at`, `title`, `body`, `html_url`, `node_id`, `draft`, `head`, and
  `base`.

  This is a test capability and has no Bash equivalent.
  """
  @spec pull(overrides :: map()) :: map()
  def pull(overrides \\ %{}) do
    Map.merge(
      %{
        "number" => 7,
        "state" => "open",
        "merged_at" => nil,
        "title" => "feat: add search",
        "body" => "why",
        "html_url" => "https://github.com/owner/repo/pull/7",
        "node_id" => "PR_node7",
        "draft" => false,
        "head" => %{"ref" => "main", "sha" => "abc123"},
        "base" => %{"ref" => "main"}
      },
      overrides
    )
  end
end
