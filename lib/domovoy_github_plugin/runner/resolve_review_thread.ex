defmodule DomovoyGithubPlugin.Runner.ResolveReviewThread do
  @moduledoc """
  Marks a review thread as resolved.

  `thread_id` is the GraphQL id of a thread, which `ListReviewThreads` gives
  as `id`. A thread that is already resolved stays resolved, and GitHub does
  not report a failure.

  The runner goes through GraphQL. A mutation that GitHub answered and
  rejected, such as one with an id that names nothing, gives
  `:github_graphql_failed`. A request that did not get an answer, or got one
  that is not `200`, gives `:github_request_failed` with the status.

  ## Inputs

    * `thread_id` — necessary. A `DomovoyCore.Type.String`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.ReviewThreadChange`.

  ## Examples

  This runner calls GitHub, so this example is illustrative.

      iex> params = %{thread_id: "PRRT_1", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.ResolveReviewThread |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "resolve_thread"}
      iex> DomovoyGithubPlugin.Runner.ResolveReviewThread.run(input, context)
      {:ok, %{id: "PRRT_1", resolved: true}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError

  input do
    field(:thread_id, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:thread_id, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{thread_id: thread_id, working_directory: directory}, %Context{node: node_name}) do
    case GithubCapabilities.resolve_review_thread(thread_id, directory) do
      {:ok, data} ->
        thread = get_in(data, ["resolveReviewThread", "thread"]) || %{}
        {:ok, %{id: thread["id"] || thread_id, resolved: thread["isResolved"] == true}}

      {:error, %{status: 200, message: message}} ->
        {:error, GithubError.graphql_failed(message, node_name, :thread_id)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, :thread_id)}
    end
  end
end
