defmodule DomovoyGithubPlugin.Runner.GetWorkflowRunLogs do
  @moduledoc """
  Downloads the logs of a workflow run to a zip archive on disk.

  GitHub keeps the logs of a run that finished. The runner writes the
  archive to `destination`, or to `.domovoy/artifacts/workflow-run-<id>.zip`
  under the working directory. A consumer opens the archive itself.

  ## Inputs

    * `run_id` — necessary. A `DomovoyCore.Type.Integer`.
    * `destination` — optional. A `DomovoyCore.Type.String`. The path of the
      archive. A relative path sits under the working directory.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.WorkflowLogs`.

  ## Examples

  This runner reads Git, calls GitHub, and writes the disk, so this example is
  illustrative.

      iex> params = %{run_id: 123, working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GetWorkflowRunLogs |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "get_logs"}
      iex> DomovoyGithubPlugin.Runner.GetWorkflowRunLogs.run(input, context)
      {:ok, %{run_id: 123, path: "/repo/.domovoy/artifacts/workflow-run-123.zip", bytes: 2048}}
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

  @artifacts_directory [".domovoy", "artifacts"]

  input do
    field(:run_id, IntegerType)
    field(:destination, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:run_id, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory
    path = destination(input.destination, input.run_id, directory)

    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory),
         {:ok, archive} <- download(repo, input.run_id, directory, node_name),
         :ok <- write(path, archive, node_name) do
      {:ok, %{run_id: input.run_id, path: path, bytes: byte_size(archive)}}
    end
  end

  @doc """
  Returns the path of the archive of `run_id`: `destination` under the
  working directory, or the default under `.domovoy/artifacts`.

  ## Examples

      iex> DomovoyGithubPlugin.Runner.GetWorkflowRunLogs.destination(nil, 123, "/repo")
      "/repo/.domovoy/artifacts/workflow-run-123.zip"

      iex> DomovoyGithubPlugin.Runner.GetWorkflowRunLogs.destination("logs/ci.zip", 123, "/repo")
      "/repo/logs/ci.zip"

      iex> DomovoyGithubPlugin.Runner.GetWorkflowRunLogs.destination("/tmp/ci.zip", 123, "/repo")
      "/tmp/ci.zip"
  """
  @spec destination(
          destination :: String.t() | nil,
          run_id :: pos_integer(),
          directory :: String.t()
        ) :: String.t()
  def destination(nil, run_id, directory),
    do: Path.join([directory | @artifacts_directory] ++ ["workflow-run-#{run_id}.zip"])

  def destination(destination, _run_id, directory) when is_binary(destination),
    do: Path.expand(destination, directory)

  @spec download(
          repo :: GithubCapabilities.repo(),
          run_id :: pos_integer(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, binary()} | {:error, Error.t()}
  defp download(repo, run_id, directory, node_name) do
    case GithubCapabilities.download_workflow_run_logs(repo.owner, repo.repo, run_id, directory) do
      {:ok, archive} -> {:ok, archive}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :run_id)}
    end
  end

  @spec write(path :: String.t(), archive :: binary(), node_name :: Node.name()) ::
          :ok | {:error, Error.t()}
  defp write(path, archive, node_name) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, archive) do
      :ok
    else
      {:error, reason} ->
        {:error, GithubError.workflow_logs_write_failed(path, reason, node_name, :destination)}
    end
  end
end
