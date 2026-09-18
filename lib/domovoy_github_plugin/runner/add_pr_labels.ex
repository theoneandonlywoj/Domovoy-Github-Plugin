defmodule DomovoyGithubPlugin.Runner.AddPrLabels do
  @moduledoc """
  Adds labels to a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. The pull request keeps the labels it has. GitHub makes a label that the repository does not have. The result lists every label the pull request has
  after the change.

  ## Inputs

    * `labels` — necessary. A `DomovoyGithubPlugin.Type.Labels`.
    * `number` — optional. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Labels`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{labels: ["ready"], working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.AddPrLabels |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "add_pr_labels"}
      iex> DomovoyGithubPlugin.Runner.AddPrLabels.run(input, context)
      {:ok, ["bug", "ready"]}
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
  alias DomovoyGithubPlugin.Type.Labels, as: LabelsType

  input do
    field(:labels, LabelsType)
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:labels, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, target} <-
           GithubCapabilities.resolve_pull(input.number, directory, node_name, :number) do
      target.repo.owner
      |> GithubCapabilities.add_labels(target.repo.repo, target.number, input.labels, directory)
      |> labels(node_name)
    end
  end

  @spec labels(result :: GithubCapabilities.result(), node_name :: Node.name()) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  defp labels({:ok, entries}, _node_name) when is_list(entries),
    do: {:ok, for(%{"name" => name} <- entries, is_binary(name), do: name)}

  defp labels({:ok, body}, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :labels)}

  defp labels({:error, failure}, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :labels)}
end
