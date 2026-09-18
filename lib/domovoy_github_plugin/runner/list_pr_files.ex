defmodule DomovoyGithubPlugin.Runner.ListPrFiles do
  @moduledoc """
  Lists the files that a pull request changes.

  The pull request is the one that `number` names, or the open one of the
  current branch. The list has every file, and not only the first page.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`. Without it the runner
      uses the open pull request of the current branch.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequestFiles`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.ListPrFiles |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "list_pr_files"}
      iex> DomovoyGithubPlugin.Runner.ListPrFiles.run(input, context)
      {:ok, [%{path: "lib/a.ex", status: "modified", additions: 3, deletions: 1, changes: 4}]}
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
    case GithubCapabilities.list_pull_files(
           target.repo.owner,
           target.repo.repo,
           target.number,
           directory
         ) do
      {:ok, files} -> {:ok, Enum.map(files, &file/1)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end

  @spec file(entry :: map()) :: map()
  defp file(entry) do
    %{
      path: entry["filename"],
      status: entry["status"],
      additions: entry["additions"] || 0,
      deletions: entry["deletions"] || 0,
      changes: entry["changes"] || 0
    }
  end
end
