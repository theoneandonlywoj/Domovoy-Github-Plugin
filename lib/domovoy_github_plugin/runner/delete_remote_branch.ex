defmodule DomovoyGithubPlugin.Runner.DeleteRemoteBranch do
  @moduledoc """
  Deletes a branch from GitHub.

  The local branch stays. A branch that GitHub does not have gives
  `:github_branch_not_found`. GitHub refuses to delete a protected branch,
  and the runner reports that as a request failure.

  ## Inputs

    * `branch` — necessary. A `DomovoyCore.Type.String`. The runner does not
      take the current branch as a default, since deleting it by accident is
      costly.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.BranchDeletion`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{branch: "feat", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.DeleteRemoteBranch |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "delete_branch"}
      iex> DomovoyGithubPlugin.Runner.DeleteRemoteBranch.run(input, context)
      {:ok, %{branch: "feat", deleted: true}}
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

  @missing_reference "Reference does not exist"

  input do
    field(:branch, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:branch, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{branch: branch, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      repo.owner
      |> GithubCapabilities.delete_ref(repo.repo, branch, directory)
      |> deleted(branch, node_name)
    end
  end

  @spec deleted(
          result :: GithubCapabilities.result(),
          branch :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp deleted({:ok, _answer}, branch, _node_name), do: {:ok, %{branch: branch, deleted: true}}

  defp deleted({:error, %{status: 422, message: message}}, branch, node_name)
       when is_binary(message) do
    if String.contains?(message, @missing_reference),
      do: {:error, GithubError.branch_not_found(branch, node_name, :branch)},
      else:
        {:error, GithubError.request_failed(%{status: 422, message: message}, node_name, :branch)}
  end

  defp deleted({:error, failure}, _branch, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :branch)}
end
