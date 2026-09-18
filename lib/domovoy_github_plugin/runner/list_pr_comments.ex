defmodule DomovoyGithubPlugin.Runner.ListPrComments do
  @moduledoc """
  Lists the conversation comments of a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. The list holds every comment, oldest first. Review comments
  on lines of the diff are not in it; `ListReviewThreads` reads those.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Comments`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.ListPrComments |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "list_pr_comments"}
      iex> DomovoyGithubPlugin.Runner.ListPrComments.run(input, context)
      {:ok, [%{id: 1001, author: "octocat", body: "LGTM", url: "https://github.com/owner/repo/pull/42#issuecomment-1001"}]}
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
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{number: number, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, target} <- GithubCapabilities.resolve_pull(number, directory, node_name, :number) do
      list(target, directory, node_name)
    end
  end

  @spec list(
          target :: GithubCapabilities.target(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, [map()]} | {:error, Error.t()}
  defp list(target, directory, node_name) do
    target.repo.owner
    |> GithubCapabilities.list_issue_comments(target.repo.repo, target.number, directory)
    |> case do
      {:ok, comments} -> {:ok, Enum.map(comments, &comment/1)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end

  @spec comment(entry :: map()) :: map()
  defp comment(entry) do
    %{
      id: entry["id"],
      author: get_in(entry, ["user", "login"]),
      body: entry["body"] || "",
      url: entry["html_url"]
    }
  end
end
