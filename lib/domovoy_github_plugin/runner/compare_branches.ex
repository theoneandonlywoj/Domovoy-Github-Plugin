defmodule DomovoyGithubPlugin.Runner.CompareBranches do
  @moduledoc """
  Compares two refs of the repository of the checkout on GitHub.

  `head` is the current branch when not named. `base` is the default branch
  of the repository when not named. The result says whether `head` is
  ahead, behind, identical, or diverged, and by how many commits.

  ## Inputs

    * `base` — optional. A `DomovoyCore.Type.String`. The default is the
      default branch of the repository.
    * `head` — optional. A `DomovoyCore.Type.String`. The default is the
      current branch.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Comparison`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.CompareBranches |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "compare"}
      iex> DomovoyGithubPlugin.Runner.CompareBranches.run(input, context)
      {:ok, %{base: "main", head: "feat", status: :ahead, ahead_by: 3, behind_by: 0, total_commits: 3}}
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
  alias DomovoyGithubPlugin.Type.Comparison, as: ComparisonType

  input do
    field(:base, StringType)
    field(:head, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory),
         {:ok, base} <- base(input.base, repo, directory, node_name) do
      head = input.head || repo.branch

      repo.owner
      |> GithubCapabilities.compare(repo.repo, base, head, directory)
      |> comparison(base, head, node_name)
    end
  end

  @spec base(
          base :: String.t() | nil,
          repo :: GithubCapabilities.repo(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, String.t()} | {:error, Error.t()}
  defp base(base, _repo, _directory, _node_name) when is_binary(base), do: {:ok, base}

  defp base(nil, repo, directory, node_name) do
    case GithubCapabilities.get_repository(repo.owner, repo.repo, directory) do
      {:ok, %{"default_branch" => default}} when is_binary(default) -> {:ok, default}
      {:ok, body} -> {:error, GithubError.request_failed(inspect(body), node_name, :base)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :base)}
    end
  end

  @spec comparison(
          result :: GithubCapabilities.result(),
          base :: String.t(),
          head :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp comparison({:ok, %{"status" => status} = entry}, base, head, _node_name)
       when is_binary(status) do
    {:ok,
     %{
       base: base,
       head: head,
       status: ComparisonType.parse_status(status),
       ahead_by: entry["ahead_by"] || 0,
       behind_by: entry["behind_by"] || 0,
       total_commits: entry["total_commits"] || 0
     }}
  end

  defp comparison({:ok, body}, _base, _head, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :head)}

  defp comparison({:error, %{status: 404}}, _base, head, node_name),
    do: {:error, GithubError.branch_not_found(head, node_name, :head)}

  defp comparison({:error, failure}, _base, _head, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :head)}
end
