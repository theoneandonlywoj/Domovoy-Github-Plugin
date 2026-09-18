defmodule DomovoyGithubPlugin.Runner.GetWorkflowRun do
  @moduledoc """
  Reads the newest workflow run of a branch.

  The branch is `branch`, or the current branch of the checkout. `workflow`
  narrows the search to one workflow, by file name such as `ci.yml` or by
  id. A branch without a run gives `:github_workflow_run_not_found`.

  ## Inputs

    * `workflow` — optional. A `DomovoyCore.Type.String`.
    * `branch` — optional. A `DomovoyCore.Type.String`. The default is the
      current branch.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.WorkflowRun`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{workflow: "ci.yml", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GetWorkflowRun |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "get_run"}
      iex> DomovoyGithubPlugin.Runner.GetWorkflowRun.run(input, context)
      {:ok, %{id: 123, name: "CI", status: :in_progress, conclusion: nil, url: "u", head_sha: "abc123"}}
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
  alias DomovoyGithubPlugin.Type.WorkflowRun, as: WorkflowRunType

  input do
    field(:workflow, StringType)
    field(:branch, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      branch = input.branch || repo.branch
      params = [branch: branch, per_page: 1]

      repo.owner
      |> GithubCapabilities.list_workflow_runs(repo.repo, input.workflow, params, directory)
      |> newest(branch, input.workflow, node_name)
    end
  end

  @doc """
  Reads a run as GitHub reports it as a `DomovoyGithubPlugin.Type.WorkflowRun`.

  `WaitForWorkflowRun` uses this too.

  ## Examples

      iex> DomovoyGithubPlugin.Runner.GetWorkflowRun.workflow_run(%{
      ...>   "id" => 1,
      ...>   "name" => "CI",
      ...>   "status" => "completed",
      ...>   "conclusion" => "success",
      ...>   "html_url" => "u",
      ...>   "head_sha" => "abc"
      ...> })
      %{id: 1, name: "CI", status: :completed, conclusion: :success, url: "u", head_sha: "abc"}
  """
  @spec workflow_run(entry :: map()) :: WorkflowRunType.state()
  def workflow_run(entry) when is_map(entry) do
    %{
      id: entry["id"],
      name: entry["name"],
      status: WorkflowRunType.parse_status(entry["status"]),
      conclusion: WorkflowRunType.parse_conclusion(entry["conclusion"]),
      url: entry["html_url"],
      head_sha: entry["head_sha"]
    }
  end

  @spec newest(
          result :: {:ok, [map()]} | {:error, GithubCapabilities.failure()},
          branch :: String.t(),
          workflow :: String.t() | nil,
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp newest({:ok, [run | _rest]}, _branch, _workflow, _node_name) when is_map(run),
    do: {:ok, workflow_run(run)}

  defp newest({:ok, []}, branch, workflow, node_name),
    do: {:error, GithubError.workflow_run_not_found(branch, workflow, node_name, :workflow)}

  defp newest({:error, failure}, _branch, _workflow, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :workflow)}
end
