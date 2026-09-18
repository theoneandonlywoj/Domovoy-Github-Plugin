defmodule DomovoyGithubPlugin.Runner.WaitForWorkflowRun do
  @moduledoc """
  Waits until a workflow run finishes.

  GitHub has no stream of the state of a run. Therefore the runner reads the
  run every `interval_ms` until its status is `:completed`, or until
  `timeout_ms` passed. A run that finished with a failure is a successful
  answer with `conclusion: :failure`. The graph decides what a failed run
  means. A run that did not finish in time gives
  `:github_workflow_run_timed_out`.

  The runner checks the time after each read. Therefore `timeout_ms: 0`
  reads the run once and reports it, or times out if it is still going. A
  pause never goes past the deadline. Therefore the runner reports a timeout
  within `interval_ms` of it, and not one interval later.

  ## Inputs

    * `run_id` — necessary. A `DomovoyCore.Type.Integer`.
    * `interval_ms` — optional. A `DomovoyCore.Type.Integer`. The default is
      10 seconds.
    * `timeout_ms` — optional. A `DomovoyCore.Type.Integer`. The default is 30
      minutes.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.WorkflowRun`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{run_id: 123, working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.WaitForWorkflowRun |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "wait_for_run"}
      iex> DomovoyGithubPlugin.Runner.WaitForWorkflowRun.run(input, context)
      {:ok, %{id: 123, name: "CI", status: :completed, conclusion: :success, url: "u", head_sha: "abc123"}}
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
  alias DomovoyGithubPlugin.Runner.GetWorkflowRun

  @typep wait() :: %{
           repo: GithubCapabilities.repo(),
           run_id: pos_integer(),
           interval_ms: non_neg_integer(),
           timeout_ms: non_neg_integer(),
           deadline: integer(),
           directory: String.t(),
           node_name: Node.name()
         }

  input do
    field(:run_id, IntegerType)
    field(:interval_ms, IntegerType, default: 10_000)
    field(:timeout_ms, IntegerType, default: 1_800_000)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:run_id, :interval_ms, :timeout_ms, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      wait = %{
        repo: repo,
        run_id: input.run_id,
        interval_ms: max(input.interval_ms, 0),
        timeout_ms: max(input.timeout_ms, 0),
        deadline: System.monotonic_time(:millisecond) + max(input.timeout_ms, 0),
        directory: directory,
        node_name: node_name
      }

      poll(wait)
    end
  end

  @spec poll(wait :: wait()) :: {:ok, map()} | {:error, Error.t()}
  defp poll(wait) do
    with {:ok, run} <- read(wait) do
      settle(run, wait)
    end
  end

  @spec settle(run :: map(), wait :: wait()) :: {:ok, map()} | {:error, Error.t()}
  defp settle(%{status: :completed} = run, _wait), do: {:ok, run}

  defp settle(_run, wait) do
    now = System.monotonic_time(:millisecond)

    if now >= wait.deadline do
      {:error,
       GithubError.workflow_run_timed_out(
         wait.run_id,
         wait.timeout_ms,
         wait.node_name,
         :timeout_ms
       )}
    else
      Process.sleep(min(wait.interval_ms, wait.deadline - now))
      poll(wait)
    end
  end

  @spec read(wait :: wait()) :: {:ok, map()} | {:error, Error.t()}
  defp read(wait) do
    wait.repo.owner
    |> GithubCapabilities.get_workflow_run(wait.repo.repo, wait.run_id, wait.directory)
    |> case do
      {:ok, %{"id" => id} = entry} when is_integer(id) ->
        {:ok, GetWorkflowRun.workflow_run(entry)}

      {:ok, body} ->
        {:error, GithubError.request_failed(inspect(body), wait.node_name, :run_id)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, wait.node_name, :run_id)}
    end
  end
end
