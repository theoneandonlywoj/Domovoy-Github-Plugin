defmodule DomovoyGithubPlugin.Runner.ListPrReviews do
  @moduledoc """
  Lists the reviews of a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. The list holds every review, oldest first. A reviewer who
  reviewed twice appears twice; the last state of each reviewer is the one
  that counts on GitHub.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequestReviews`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.ListPrReviews |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "list_pr_reviews"}
      iex> DomovoyGithubPlugin.Runner.ListPrReviews.run(input, context)
      {:ok, [%{id: 500, state: :approved, author: "octocat", body: "", url: "u"}]}
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
  alias DomovoyGithubPlugin.Runner.ReviewPr

  input do
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{number: number, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, target} <- GithubCapabilities.resolve_pull(number, directory, node_name, :number) do
      list(target, directory, node_name)
    end
  end

  @spec list(
          target :: GithubCapabilities.target(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, [map()]} | {:error, Error.t()}
  defp list(target, directory, node_name) do
    case GithubCapabilities.list_reviews(
           target.repo.owner,
           target.repo.repo,
           target.number,
           directory
         ) do
      {:ok, reviews} -> {:ok, Enum.map(reviews, &ReviewPr.review/1)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end
end
