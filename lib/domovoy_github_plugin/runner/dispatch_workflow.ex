defmodule DomovoyGithubPlugin.Runner.DispatchWorkflow do
  @moduledoc """
  Starts a workflow.

  The workflow must have a `workflow_dispatch` trigger. It runs on `ref`, or
  on the current branch of the checkout. GitHub does not name the run it
  starts. Therefore the result says that the run began, and `GetWorkflowRun`
  reads it after a moment.

  ## Inputs

    * `workflow` — necessary. A `DomovoyCore.Type.String`. The file name, such
      as `ci.yml`, or the id.
    * `ref` — optional. A `DomovoyCore.Type.String`. The default is the current
      branch.
    * `inputs` — optional. A `DomovoyCore.Type.Map` with the inputs of the
      workflow. The default is none.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.WorkflowDispatch`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{workflow: "deploy.yml", inputs: %{"environment" => "staging"}, working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.DispatchWorkflow |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "dispatch"}
      iex> DomovoyGithubPlugin.Runner.DispatchWorkflow.run(input, context)
      {:ok, %{workflow: "deploy.yml", ref: "main", dispatched: true}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Map, as: MapType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError

  input do
    field(:workflow, StringType)
    field(:ref, StringType)
    field(:inputs, MapType, default: %{})
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:workflow, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      ref = input.ref || repo.branch

      repo.owner
      |> GithubCapabilities.dispatch_workflow(
        repo.repo,
        input.workflow,
        ref,
        input.inputs,
        directory
      )
      |> dispatched(input.workflow, ref, node_name)
    end
  end

  @spec dispatched(
          result :: GithubCapabilities.result(),
          workflow :: String.t(),
          ref :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp dispatched({:ok, _answer}, workflow, ref, _node_name),
    do: {:ok, %{workflow: workflow, ref: ref, dispatched: true}}

  defp dispatched({:error, failure}, _workflow, _ref, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :workflow)}
end
