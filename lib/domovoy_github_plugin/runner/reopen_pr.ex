defmodule DomovoyGithubPlugin.Runner.ReopenPr do
  @moduledoc """
  Reopens a closed pull request.

  The pull request is the one that `number` names, or the newest closed one of
  the current branch. GitHub lists a merged pull request as closed and cannot
  reopen it. Therefore the search skips a merged one, and a `number` that
  names a merged one gives a failure from GitHub.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`. Without it the runner
      reopens the newest closed pull request of the current branch that was
      not merged.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequestChange`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{number: 42, working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.ReopenPr |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "reopen_pr"}
      iex> DomovoyGithubPlugin.Runner.ReopenPr.run(input, context)
      {:ok, %{action: "reopened", number: 42, url: "https://github.com/owner/repo/pull/42"}}
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
    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :number),
         {:ok, number} <- closed_number(repo, number, directory, node_name) do
      reopen(repo, number, directory, node_name)
    end
  end

  @spec closed_number(
          repo :: GithubCapabilities.repo(),
          number :: pos_integer() | nil,
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, pos_integer()} | {:error, Error.t()}
  defp closed_number(_repo, number, _directory, _node_name) when is_integer(number),
    do: {:ok, number}

  defp closed_number(repo, nil, directory, node_name) do
    head = "#{repo.owner}:#{repo.branch}"

    case GithubCapabilities.list_pulls(repo.owner, repo.repo, head, "closed", directory) do
      {:ok, pulls} when is_list(pulls) ->
        reopenable_number(pulls, head, node_name)

      {:ok, body} ->
        {:error, GithubError.request_failed(inspect(body), node_name, :number)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end

  @spec reopenable_number(pulls :: [map()], head :: String.t(), node_name :: Node.name()) ::
          {:ok, pos_integer()} | {:error, Error.t()}
  defp reopenable_number(pulls, head, node_name) do
    case Enum.find(pulls, &reopenable?/1) do
      %{"number" => number} -> {:ok, number}
      nil -> {:error, GithubError.pull_request_not_found(nil, head, node_name, :number)}
    end
  end

  @spec reopenable?(pull :: term()) :: boolean()
  defp reopenable?(%{"number" => number} = pull) when is_integer(number),
    do: is_nil(pull["merged_at"])

  defp reopenable?(_pull), do: false

  @spec reopen(
          repo :: GithubCapabilities.repo(),
          number :: pos_integer(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp reopen(repo, number, directory, node_name) do
    payload = %{"state" => "open"}

    repo.owner
    |> GithubCapabilities.update_pull(repo.repo, number, payload, directory)
    |> case do
      {:ok, pull} when is_map(pull) ->
        {:ok, %{action: "reopened", number: pull["number"], url: pull["html_url"]}}

      {:ok, body} ->
        {:error, GithubError.request_failed(inspect(body), node_name, :number)}

      {:error, %{status: 404}} ->
        {:error, GithubError.pull_request_not_found(number, nil, node_name, :number)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end
end
