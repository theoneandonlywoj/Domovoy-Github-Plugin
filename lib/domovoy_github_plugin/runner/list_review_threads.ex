defmodule DomovoyGithubPlugin.Runner.ListReviewThreads do
  @moduledoc """
  Lists the review threads of a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. Each thread holds its first comment, whether it is
  resolved, and the `comment_id` that `ReplyToReviewComment` takes. The
  runner reads the first 100 threads.

  The runner goes through GraphQL. A query that GitHub answered and rejected
  gives `:github_graphql_failed`. A request that did not get an answer, or
  got one that is not `200`, gives `:github_request_failed` with the status.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.ReviewThreads`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.ListReviewThreads |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "list_threads"}
      iex> DomovoyGithubPlugin.Runner.ListReviewThreads.run(input, context)
      {:ok,
       [
         %{
           id: "PRRT_1",
           resolved: false,
           outdated: false,
           path: "lib/a.ex",
           line: 12,
           body: "Rename this.",
           author: "octocat",
           comment_id: 900
         }
       ]}
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
    target.repo.owner
    |> GithubCapabilities.list_review_threads(target.repo.repo, target.number, directory)
    |> case do
      {:ok, data} ->
        nodes = get_in(data, ["repository", "pullRequest", "reviewThreads", "nodes"]) || []
        {:ok, Enum.map(nodes, &thread/1)}

      {:error, %{status: 200, message: message}} ->
        {:error, GithubError.graphql_failed(message, node_name, :number)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end

  @spec thread(node :: map()) :: map()
  defp thread(node) do
    first = node |> get_in(["comments", "nodes"]) |> List.wrap() |> List.first() || %{}

    %{
      id: node["id"],
      resolved: node["isResolved"] == true,
      outdated: node["isOutdated"] == true,
      path: node["path"],
      line: node["line"],
      body: first["body"] || "",
      author: get_in(first, ["author", "login"]),
      comment_id: first["databaseId"]
    }
  end
end
