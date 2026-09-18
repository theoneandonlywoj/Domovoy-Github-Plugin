defmodule DomovoyGithubPlugin.Runner.GetWorkflowJobs do
  @moduledoc """
  Reads the jobs of a workflow run, with the steps of each.

  A consumer reads the jobs to learn which step of a failed run failed.

  ## Inputs

    * `run_id` — necessary. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.WorkflowJobs`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{run_id: 123, working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GetWorkflowJobs |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "get_jobs"}
      iex> DomovoyGithubPlugin.Runner.GetWorkflowJobs.run(input, context)
      {:ok,
       [
         %{
           id: 1,
           name: "test",
           status: "completed",
           conclusion: "failure",
           url: "u",
           steps: [%{number: 1, name: "mix test", status: "completed", conclusion: "failure"}]
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
    field(:run_id, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:run_id, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{run_id: run_id, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      jobs(repo, run_id, directory, node_name)
    end
  end

  @spec jobs(
          repo :: GithubCapabilities.repo(),
          run_id :: pos_integer(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, [map()]} | {:error, Error.t()}
  defp jobs(repo, run_id, directory, node_name) do
    case GithubCapabilities.list_workflow_jobs(repo.owner, repo.repo, run_id, directory) do
      {:ok, jobs} -> {:ok, Enum.map(jobs, &job/1)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :run_id)}
    end
  end

  @spec job(entry :: map()) :: map()
  defp job(entry) do
    %{
      id: entry["id"],
      name: entry["name"] || "",
      status: entry["status"],
      conclusion: entry["conclusion"],
      url: entry["html_url"],
      steps: entry["steps"] |> List.wrap() |> Enum.map(&step/1)
    }
  end

  @spec step(entry :: map()) :: map()
  defp step(entry) do
    %{
      number: entry["number"] || 0,
      name: entry["name"] || "",
      status: entry["status"],
      conclusion: entry["conclusion"]
    }
  end
end
