defmodule DomovoyGithubPlugin.Runner.ListPrCommits do
  @moduledoc """
  Lists the commits of a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. The list has every commit in the order of the branch.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`. Without it the runner
      uses the open pull request of the current branch.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequestCommits`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.ListPrCommits |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "list_pr_commits"}
      iex> DomovoyGithubPlugin.Runner.ListPrCommits.run(input, context)
      {:ok, [%{sha: "6dcb09b", message: "feat: add search", author: "octocat"}]}
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
    case GithubCapabilities.list_pull_commits(
           target.repo.owner,
           target.repo.repo,
           target.number,
           directory
         ) do
      {:ok, commits} -> {:ok, Enum.map(commits, &commit/1)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end

  @spec commit(entry :: map()) :: map()
  defp commit(entry) do
    details = entry["commit"] || %{}

    %{
      sha: entry["sha"],
      message: details["message"] || "",
      author: author(entry["author"], details["author"])
    }
  end

  @spec author(github_author :: term(), commit_author :: term()) :: String.t() | nil
  defp author(%{"login" => login}, _commit_author) when is_binary(login), do: login
  defp author(_github_author, %{"name" => name}) when is_binary(name), do: name
  defp author(_github_author, _commit_author), do: nil
end
