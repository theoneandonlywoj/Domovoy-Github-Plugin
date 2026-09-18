defmodule DomovoyGithubPlugin.Runner.UpdateIssue do
  @moduledoc """
  Changes an issue of the repository of the checkout.

  The runner sends only the inputs the caller gave. Therefore a run with only
  `state` closes or reopens the issue and keeps its text. A number that
  names nothing gives `:github_issue_not_found`.

  ## Inputs

    * `number` — necessary. A `DomovoyCore.Type.Integer`.
    * `title` — optional. A `DomovoyCore.Type.String`.
    * `body` — optional. A `DomovoyGithubPlugin.Type.CommentBody`.
    * `state` — optional. A `DomovoyCore.Type.String`. It is `"open"` or
      `"closed"`.
    * `labels` — optional. A `DomovoyGithubPlugin.Type.Labels`. It replaces
      every label.
    * `assignees` — optional. A `DomovoyGithubPlugin.Type.Assignees`. It
      replaces every assignee.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Issue`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{number: 9, state: "closed", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.UpdateIssue |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "close_issue"}
      iex> DomovoyGithubPlugin.Runner.UpdateIssue.run(input, context)
      {:ok,
       %{
         number: 9,
         title: "Flaky test",
         body: "It fails on CI.",
         state: :closed,
         labels: ["bug"],
         assignees: [],
         url: "https://github.com/owner/repo/issues/9"
       }}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Runner.GetIssue
  alias DomovoyGithubPlugin.Type.Assignees, as: AssigneesType
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType
  alias DomovoyGithubPlugin.Type.Labels, as: LabelsType

  input do
    field(:number, IntegerType)
    field(:title, StringType)
    field(:body, CommentBodyType)
    field(:state, StringType)
    field(:labels, LabelsType)
    field(:assignees, AssigneesType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:number, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      repo.owner
      |> GithubCapabilities.update_issue(repo.repo, input.number, payload(input), directory)
      |> GetIssue.issue(input.number, node_name)
    end
  end

  @spec payload(input :: Input.t()) :: map()
  defp payload(%Input{} = input) do
    %{
      "title" => input.title,
      "body" => input.body,
      "state" => input.state,
      "labels" => input.labels,
      "assignees" => input.assignees
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
