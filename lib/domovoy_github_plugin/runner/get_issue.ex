defmodule DomovoyGithubPlugin.Runner.GetIssue do
  @moduledoc """
  Reads an issue of the repository of the checkout.

  An issue has no branch. Therefore `number` is necessary. A number that
  names nothing gives `:github_issue_not_found`.

  ## Inputs

    * `number` — necessary. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Issue`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{number: 9, working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GetIssue |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "get_issue"}
      iex> DomovoyGithubPlugin.Runner.GetIssue.run(input, context)
      {:ok,
       %{
         number: 9,
         title: "Flaky test",
         body: "It fails on CI.",
         state: :open,
         labels: ["bug"],
         assignees: [],
         url: "https://github.com/owner/repo/issues/9"
       }}
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
  alias DomovoyGithubPlugin.Runner.CreateIssue

  input do
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:number, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{number: number, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      repo.owner
      |> GithubCapabilities.get_issue(repo.repo, number, directory)
      |> issue(number, node_name)
    end
  end

  @doc """
  Reads the answer of GitHub to a request for issue `number`.

  `UpdateIssue` uses this too. A `404` gives `:github_issue_not_found`.
  """
  @spec issue(
          result :: GithubCapabilities.result(),
          number :: pos_integer(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  def issue({:ok, %{"number" => found} = entry}, _number, _node_name) when is_integer(found),
    do: {:ok, CreateIssue.issue(entry)}

  def issue({:ok, body}, _number, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :number)}

  def issue({:error, %{status: 404}}, number, node_name),
    do: {:error, GithubError.issue_not_found(number, node_name, :number)}

  def issue({:error, failure}, _number, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :number)}
end
