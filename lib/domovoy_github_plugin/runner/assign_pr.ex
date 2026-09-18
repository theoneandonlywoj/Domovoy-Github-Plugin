defmodule DomovoyGithubPlugin.Runner.AssignPr do
  @moduledoc """
  Assigns people to a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. The pull request keeps the assignees it has. GitHub ignores
  a login that cannot be assigned and does not report a failure. The result
  lists every assignee the pull request has after the change. Therefore a
  caller checks the result for the login it sent.

  ## Inputs

    * `assignees` — necessary. A `DomovoyGithubPlugin.Type.Assignees`.
    * `number` — optional. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Assignees`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{assignees: ["octocat"], working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.AssignPr |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "assign_pr"}
      iex> DomovoyGithubPlugin.Runner.AssignPr.run(input, context)
      {:ok, ["octocat"]}
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
  alias DomovoyGithubPlugin.Type.Assignees, as: AssigneesType

  input do
    field(:assignees, AssigneesType)
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:assignees, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, target} <-
           GithubCapabilities.resolve_pull(input.number, directory, node_name, :number) do
      target.repo.owner
      |> GithubCapabilities.add_assignees(
        target.repo.repo,
        target.number,
        input.assignees,
        directory
      )
      |> assignees(node_name)
    end
  end

  @spec assignees(result :: GithubCapabilities.result(), node_name :: Node.name()) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  defp assignees({:ok, %{"assignees" => entries}}, _node_name) when is_list(entries),
    do: {:ok, for(%{"login" => login} <- entries, is_binary(login), do: login)}

  defp assignees({:ok, body}, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :assignees)}

  defp assignees({:error, failure}, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :assignees)}
end
