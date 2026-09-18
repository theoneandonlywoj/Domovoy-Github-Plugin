defmodule DomovoyGithubPlugin.Runner.GetBranch do
  @moduledoc """
  Reads a branch of the repository of the checkout as GitHub knows it.

  The branch is `branch`, or the current branch. A branch that GitHub does
  not have, such as one not pushed yet, gives `:github_branch_not_found`.

  ## Inputs

    * `branch` — optional. A `DomovoyCore.Type.String`. The default is the
      current branch.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Branch`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{branch: "main", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GetBranch |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "get_branch"}
      iex> DomovoyGithubPlugin.Runner.GetBranch.run(input, context)
      {:ok, %{name: "main", sha: "abc123", protected: true}}
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

  input do
    field(:branch, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{branch: branch, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      branch = branch || repo.branch

      repo.owner
      |> GithubCapabilities.get_branch(repo.repo, branch, directory)
      |> found(branch, node_name)
    end
  end

  @spec found(
          result :: GithubCapabilities.result(),
          branch :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp found({:ok, %{"name" => name, "commit" => %{"sha" => sha}} = entry}, _branch, _node_name)
       when is_binary(name) and is_binary(sha),
       do: {:ok, %{name: name, sha: sha, protected: entry["protected"] == true}}

  defp found({:ok, body}, _branch, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :branch)}

  defp found({:error, %{status: 404}}, branch, node_name),
    do: {:error, GithubError.branch_not_found(branch, node_name, :branch)}

  defp found({:error, failure}, _branch, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :branch)}
end
