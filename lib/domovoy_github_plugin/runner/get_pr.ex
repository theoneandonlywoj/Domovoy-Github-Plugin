defmodule DomovoyGithubPlugin.Runner.GetPr do
  @moduledoc """
  Reads the GitHub pull request for the current branch of a checkout.

  The repository and branch come from the `origin` remote and `HEAD`. A branch
  without a pull request gives `state: :not_found` and does not fail.

  GitHub reports a merged pull request as closed. This runner gives `:merged`
  for a merged pull request. It gives `:closed` for one closed without a merge.

  ## Inputs

    * `state` — optional. A `DomovoyCore.Type.String`. It is `"open"`, `"closed"`,
      or `"all"`. The default is `"all"`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequest`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{state: "all", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GetPr |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "get_pr"}
      iex> DomovoyGithubPlugin.Runner.GetPr.run(input, context)
      {:ok,
       %{
         state: :open,
         number: 42,
         title: "Implement additional operations",
         body: "Closes BRO-19.",
         url: "https://github.com/theoneandonlywoj/brownie/pull/42"
       }}

  A branch without a pull request gives a successful result:

      iex> DomovoyGithubPlugin.Runner.GetPr.run(input, context)
      {:ok, %{state: :not_found, number: nil, title: nil, body: nil, url: nil}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError
  alias DomovoyGithubPlugin.Type.PullRequest, as: PullRequestType

  @state_filters ["open", "closed", "all"]

  input do
    field(:state, StringType, default: "all")
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:state, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{state: state, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, state} <- validated_state_filter(state, node_name),
         {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory),
         {:ok, pulls} <- list_pulls(repo, state, directory, node_name) do
      {:ok, lookup(pulls)}
    end
  end

  @doc """
  Returns every search filter that the `state` input accepts.

  These values are GitHub API filters. They are not pull request states.

  ## Examples

      iex> DomovoyGithubPlugin.Runner.GetPr.state_filters()
      ["open", "closed", "all"]
  """
  @spec state_filters() :: [String.t()]
  def state_filters, do: @state_filters

  @spec validated_state_filter(state_filter :: String.t(), node_name :: Node.name()) ::
          {:ok, String.t()} | {:error, Error.t()}
  defp validated_state_filter(state_filter, _node_name) when state_filter in @state_filters,
    do: {:ok, state_filter}

  defp validated_state_filter(state_filter, node_name) do
    {:error,
     GithubError.invalid_pull_request_state(
       state_filter,
       @state_filters,
       node_name,
       :state
     )}
  end

  @spec list_pulls(
          repo :: GithubCapabilities.repo(),
          state :: String.t(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, [map()]} | {:error, Error.t()}
  defp list_pulls(repo, state, directory, node_name) do
    head = "#{repo.owner}:#{repo.branch}"

    case GithubCapabilities.list_pulls(repo.owner, repo.repo, head, state, directory) do
      {:ok, pulls} when is_list(pulls) -> {:ok, pulls}
      {:ok, body} -> {:error, GithubError.request_failed(inspect(body), node_name, :state)}
      {:error, reason} -> {:error, GithubError.request_failed(reason, node_name, :state)}
    end
  end

  @spec lookup(pulls :: [map()]) :: map()
  defp lookup([]),
    do: %{state: :not_found, number: nil, title: nil, body: nil, url: nil}

  defp lookup([pull | _rest]) do
    %{
      state: PullRequestType.parse_state(pull["state"], pull["merged_at"]),
      number: pull["number"],
      title: pull["title"],
      body: pull["body"],
      url: pull["html_url"]
    }
  end
end
