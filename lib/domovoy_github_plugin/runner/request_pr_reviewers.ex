defmodule DomovoyGithubPlugin.Runner.RequestPrReviewers do
  @moduledoc """
  Asks people and teams to review a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. GitHub keeps the reviewers that were already asked. The
  result lists every pending reviewer of the pull request.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`. Without it the runner
      uses the open pull request of the current branch.
    * `reviewers` — optional. A `DomovoyGithubPlugin.Type.Names` of logins.
      The default is none.
    * `team_reviewers` — optional. A `DomovoyGithubPlugin.Type.Names` of team
      slugs. The default is none.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.ReviewRequest`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{reviewers: ["octocat"], working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.RequestPrReviewers |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "request_reviewers"}
      iex> DomovoyGithubPlugin.Runner.RequestPrReviewers.run(input, context)
      {:ok,
       %{
         number: 42,
         reviewers: ["octocat"],
         team_reviewers: [],
         url: "https://github.com/owner/repo/pull/42"
       }}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError
  alias DomovoyGithubPlugin.Type.Names, as: NamesType

  input do
    field(:number, IntegerType)
    field(:reviewers, NamesType, default: [])
    field(:team_reviewers, NamesType, default: [])
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    with {:ok, target} <-
           GithubCapabilities.resolve_pull(
             input.number,
             input.working_directory,
             node_name,
             :number
           ) do
      payload = %{"reviewers" => input.reviewers, "team_reviewers" => input.team_reviewers}
      request(target, payload, input.working_directory, node_name)
    end
  end

  @spec request(
          target :: GithubCapabilities.target(),
          payload :: map(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp request(target, payload, directory, node_name) do
    target.repo.owner
    |> GithubCapabilities.request_reviewers(target.repo.repo, target.number, payload, directory)
    |> case do
      {:ok, pull} when is_map(pull) ->
        {:ok,
         %{
           number: pull["number"] || target.number,
           reviewers: names(pull["requested_reviewers"], "login"),
           team_reviewers: names(pull["requested_teams"], "slug"),
           url: pull["html_url"] || target.pull["html_url"]
         }}

      {:ok, body} ->
        {:error, GithubError.request_failed(inspect(body), node_name, :reviewers)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, :reviewers)}
    end
  end

  @spec names(entries :: term(), key :: String.t()) :: [String.t()]
  defp names(entries, key) when is_list(entries) do
    for %{^key => name} <- entries, is_binary(name), do: name
  end

  defp names(_entries, _key), do: []
end
