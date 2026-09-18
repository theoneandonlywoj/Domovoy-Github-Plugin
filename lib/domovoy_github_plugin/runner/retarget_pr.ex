defmodule DomovoyGithubPlugin.Runner.RetargetPr do
  @moduledoc """
  Changes the base branch of a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. The new base is `base_branch`, or the default branch of the
  repository. A stacked pull request moves to the default branch this way when
  its parent merges.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`. Without it the runner
      uses the open pull request of the current branch.
    * `base_branch` — optional. A `DomovoyCore.Type.String`. Without it the
      runner reads the default branch of the repository from GitHub.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequestChange`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.RetargetPr |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "retarget_pr"}
      iex> DomovoyGithubPlugin.Runner.RetargetPr.run(input, context)
      {:ok, %{action: "retargeted", number: 43, url: "https://github.com/owner/repo/pull/43"}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError

  input do
    field(:number, IntegerType)
    field(:base_branch, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, target} <-
           GithubCapabilities.resolve_pull(input.number, directory, node_name, :number),
         {:ok, base} <- base_branch(input.base_branch, target.repo, directory, node_name) do
      retarget(target, base, directory, node_name)
    end
  end

  @spec base_branch(
          base_branch :: String.t() | nil,
          repo :: GithubCapabilities.repo(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, String.t()} | {:error, Error.t()}
  defp base_branch(base_branch, _repo, _directory, _node_name) when is_binary(base_branch),
    do: {:ok, base_branch}

  defp base_branch(nil, repo, directory, node_name) do
    case GithubCapabilities.get_repository(repo.owner, repo.repo, directory) do
      {:ok, %{"default_branch" => default}} when is_binary(default) -> {:ok, default}
      {:ok, body} -> {:error, GithubError.request_failed(inspect(body), node_name, :base_branch)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :base_branch)}
    end
  end

  @spec retarget(
          target :: GithubCapabilities.target(),
          base :: String.t(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp retarget(target, base, directory, node_name) do
    payload = %{"base" => base}

    target.repo.owner
    |> GithubCapabilities.update_pull(target.repo.repo, target.number, payload, directory)
    |> case do
      {:ok, pull} when is_map(pull) ->
        {:ok, %{action: "retargeted", number: pull["number"], url: pull["html_url"]}}

      {:ok, body} ->
        {:error, GithubError.request_failed(inspect(body), node_name, :base_branch)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, :base_branch)}
    end
  end
end
