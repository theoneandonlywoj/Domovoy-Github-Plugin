defmodule DomovoyGithubPlugin.Runner.CreateIssue do
  @moduledoc """
  Opens an issue in the repository of the checkout.

  ## Inputs

    * `title` — necessary. A `DomovoyCore.Type.String`.
    * `body` — optional. A `DomovoyGithubPlugin.Type.CommentBody`. The default
      is empty.
    * `labels` — optional. A `DomovoyGithubPlugin.Type.Labels`. The default is
      none.
    * `assignees` — optional. A `DomovoyGithubPlugin.Type.Assignees`. The
      default is none.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Issue`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{title: "Flaky test", body: "It fails on CI.", labels: ["bug"], working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.CreateIssue |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "create_issue"}
      iex> DomovoyGithubPlugin.Runner.CreateIssue.run(input, context)
      {:ok,
       %{
         number: 9,
         title: "Flaky test",
         body: "It fails on CI.",
         state: :open,
         labels: ["bug"],
         assignees: [],
         url: "https://github.com/owner/repo/issues/9"
       }}

  An issue as GitHub reports it, read as a `DomovoyGithubPlugin.Type.Issue`:

      iex> DomovoyGithubPlugin.Runner.CreateIssue.issue(%{
      ...>   "number" => 9,
      ...>   "title" => "Bug",
      ...>   "body" => nil,
      ...>   "state" => "closed",
      ...>   "labels" => [%{"name" => "bug"}],
      ...>   "assignees" => [%{"login" => "octocat"}],
      ...>   "html_url" => "u"
      ...> })
      %{number: 9, title: "Bug", body: "", state: :closed, labels: ["bug"], assignees: ["octocat"], url: "u"}
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
  alias DomovoyGithubPlugin.Type.Assignees, as: AssigneesType
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType
  alias DomovoyGithubPlugin.Type.Issue, as: IssueType
  alias DomovoyGithubPlugin.Type.Labels, as: LabelsType

  input do
    field(:title, StringType)
    field(:body, CommentBodyType, default: "")
    field(:labels, LabelsType, default: [])
    field(:assignees, AssigneesType, default: [])
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:title, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      payload = %{
        "title" => input.title,
        "body" => input.body,
        "labels" => input.labels,
        "assignees" => input.assignees
      }

      repo.owner
      |> GithubCapabilities.create_issue(repo.repo, payload, directory)
      |> created(node_name)
    end
  end

  @doc """
  Reads an issue as GitHub reports it as a `DomovoyGithubPlugin.Type.Issue`.

  `GetIssue` and `UpdateIssue` use this too.

  ## Examples

      iex> DomovoyGithubPlugin.Runner.CreateIssue.issue(%{"number" => 1, "title" => "t", "state" => "open"})
      %{number: 1, title: "t", body: "", state: :open, labels: [], assignees: [], url: nil}
  """
  @spec issue(entry :: map()) :: IssueType.state()
  def issue(entry) when is_map(entry) do
    %{
      number: entry["number"],
      title: entry["title"] || "",
      body: entry["body"] || "",
      state: IssueType.parse_state(entry["state"]),
      labels: names(entry["labels"], "name"),
      assignees: names(entry["assignees"], "login"),
      url: entry["html_url"]
    }
  end

  @spec names(entries :: term(), key :: String.t()) :: [String.t()]
  defp names(entries, key) when is_list(entries),
    do: for(%{^key => name} <- entries, is_binary(name), do: name)

  defp names(_entries, _key), do: []

  @spec created(result :: GithubCapabilities.result(), node_name :: Node.name()) ::
          {:ok, map()} | {:error, Error.t()}
  defp created({:ok, %{"number" => number} = entry}, _node_name) when is_integer(number),
    do: {:ok, issue(entry)}

  defp created({:ok, body}, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :title)}

  defp created({:error, failure}, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :title)}
end
