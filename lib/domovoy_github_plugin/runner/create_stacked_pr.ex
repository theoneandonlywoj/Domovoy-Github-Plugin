defmodule DomovoyGithubPlugin.Runner.CreateStackedPr do
  @moduledoc """
  Opens or changes a pull request that sits on top of another branch.

  A stacked pull request has `parent_branch` as its base and not the default
  branch. The first run opens the pull request. Each later run changes the
  open pull request and sets its base to `parent_branch` again. Therefore a
  stack stays in order when a parent branch changes.

  ## Inputs

    * `title` — necessary. A `DomovoyCore.Type.String`.
    * `body` — necessary. A `DomovoyCore.Type.String`.
    * `parent_branch` — necessary. A `DomovoyCore.Type.String`. The branch the
      pull request targets.
    * `draft` — optional. A `DomovoyCore.Type.Boolean`. The default is `false`.
      GitHub reads it only when the runner opens the pull request.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequestChange`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{title: "feat: b", body: "on top of a", parent_branch: "feat-a", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.CreateStackedPr |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "create_stacked_pr"}
      iex> DomovoyGithubPlugin.Runner.CreateStackedPr.run(input, context)
      {:ok, %{action: "created", number: 43, url: "https://github.com/owner/repo/pull/43"}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError

  input do
    field(:title, StringType)
    field(:body, StringType)
    field(:parent_branch, StringType)
    field(:draft, BooleanType, default: false)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:title, :body, :parent_branch, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    with {:ok, repo} <-
           GithubCapabilities.current_repo(input.working_directory, node_name, :working_directory) do
      create_body = %{
        "title" => input.title,
        "body" => input.body,
        "head" => repo.branch,
        "base" => input.parent_branch,
        "draft" => input.draft
      }

      update_body = %{"title" => input.title, "body" => input.body, "base" => input.parent_branch}

      repo.owner
      |> GithubCapabilities.upsert_pull(
        repo.repo,
        repo.branch,
        create_body,
        update_body,
        input.working_directory
      )
      |> change(node_name)
    end
  end

  @spec change(
          result :: {:ok, {:created | :updated, map()}} | {:error, GithubCapabilities.failure()},
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp change({:ok, {action, pull}}, _node_name),
    do: {:ok, %{action: Atom.to_string(action), number: pull["number"], url: pull["html_url"]}}

  defp change({:error, failure}, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :parent_branch)}
end
