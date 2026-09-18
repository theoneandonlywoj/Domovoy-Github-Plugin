defmodule DomovoyGithubPlugin.Runner.UpdatePrBranch do
  @moduledoc """
  Brings the head branch of a pull request up to date with its base.

  The pull request is the one that `number` names, or the open one of the
  current branch. GitHub starts the update and answers before it finishes.
  Therefore the result says that the update began. A later `GetChecks` or
  `GetPr` reads the outcome.

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
      iex> input = DomovoyGithubPlugin.Runner.UpdatePrBranch |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "update_pr_branch"}
      iex> DomovoyGithubPlugin.Runner.UpdatePrBranch.run(input, context)
      {:ok, %{action: "branch_updated", number: 42, url: "https://github.com/owner/repo/pull/42"}}
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
      update(target, directory, node_name)
    end
  end

  @spec update(
          target :: GithubCapabilities.target(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp update(target, directory, node_name) do
    target.repo.owner
    |> GithubCapabilities.update_pull_branch(target.repo.repo, target.number, directory)
    |> case do
      {:ok, _answer} ->
        {:ok, %{action: "branch_updated", number: target.number, url: target.pull["html_url"]}}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end
end
