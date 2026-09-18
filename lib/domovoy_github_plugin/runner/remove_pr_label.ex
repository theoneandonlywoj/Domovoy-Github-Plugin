defmodule DomovoyGithubPlugin.Runner.RemovePrLabel do
  @moduledoc """
  Removes one label from a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. A label the pull request does not have gives
  `:github_label_not_found`. The result lists every label the pull request
  has after the change.

  ## Inputs

    * `label` — necessary. A `DomovoyCore.Type.String`.
    * `number` — optional. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Labels`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{label: "wip", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.RemovePrLabel |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "remove_pr_label"}
      iex> DomovoyGithubPlugin.Runner.RemovePrLabel.run(input, context)
      {:ok, ["ready"]}
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

  input do
    field(:label, StringType)
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:label, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, target} <-
           GithubCapabilities.resolve_pull(input.number, directory, node_name, :number) do
      target.repo.owner
      |> GithubCapabilities.remove_label(target.repo.repo, target.number, input.label, directory)
      |> labels(input.label, target.number, node_name)
    end
  end

  @spec labels(
          result :: GithubCapabilities.result(),
          label :: String.t(),
          number :: pos_integer(),
          node_name :: Node.name()
        ) :: {:ok, [String.t()]} | {:error, Error.t()}
  defp labels({:ok, entries}, _label, _number, _node_name) when is_list(entries),
    do: {:ok, for(%{"name" => name} <- entries, is_binary(name), do: name)}

  defp labels({:ok, body}, _label, _number, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :label)}

  defp labels({:error, %{status: 404}}, label, number, node_name),
    do: {:error, GithubError.label_not_found(label, number, node_name, :label)}

  defp labels({:error, failure}, _label, _number, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :label)}
end
