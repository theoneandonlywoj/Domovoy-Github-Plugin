defmodule DomovoyGithubPlugin.Runner.MarkPrReadyForReview do
  @moduledoc """
  Marks a draft pull request as ready for review.

  The pull request is the one that `number` names, or the open one of the
  current branch. The REST API of GitHub cannot do this. Therefore the runner
  goes through GraphQL with the `node_id` of the pull request. A pull request
  that is not a draft stays as it is, and GitHub does not report a failure.

  A mutation that GitHub answered and rejected gives `:github_graphql_failed`.
  A request that did not get an answer, or got one that is not `200`, gives
  `:github_request_failed` with the status.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`. Without it the runner
      uses the open pull request of the current branch.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequestChange`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.MarkPrReadyForReview |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "ready_for_review"}
      iex> DomovoyGithubPlugin.Runner.MarkPrReadyForReview.run(input, context)
      {:ok, %{action: "ready_for_review", number: 42, url: "https://github.com/owner/repo/pull/42"}}
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

  input do
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{number: number, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, target} <- GithubCapabilities.resolve_pull(number, directory, node_name, :number),
         {:ok, node_id} <- node_id(target, node_name) do
      mark(target, node_id, directory, node_name)
    end
  end

  @spec node_id(target :: GithubCapabilities.target(), node_name :: Node.name()) ::
          {:ok, String.t()} | {:error, Error.t()}
  defp node_id(%{pull: %{"node_id" => node_id}}, _node_name) when is_binary(node_id),
    do: {:ok, node_id}

  defp node_id(target, node_name) do
    reason = "pull request #{target.number} has no node_id"
    {:error, GithubError.request_failed(reason, node_name, :number)}
  end

  @spec mark(
          target :: GithubCapabilities.target(),
          node_id :: String.t(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp mark(target, node_id, directory, node_name) do
    case GithubCapabilities.mark_pull_ready_for_review(node_id, directory) do
      {:ok, data} ->
        pull = get_in(data, ["markPullRequestReadyForReview", "pullRequest"]) || %{}

        {:ok,
         %{
           action: "ready_for_review",
           number: pull["number"] || target.number,
           url: pull["url"] || target.pull["html_url"]
         }}

      {:error, %{status: 200, message: message}} ->
        {:error, GithubError.graphql_failed(message, node_name, :number)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end
end
