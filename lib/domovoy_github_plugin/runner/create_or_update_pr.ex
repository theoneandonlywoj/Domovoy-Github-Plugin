defmodule DomovoyGithubPlugin.Runner.CreateOrUpdatePr do
  @moduledoc """
  Opens or changes a pull request for the current branch of a checkout.

  The first run opens the pull request. Each later run changes the open pull
  request. The repository and branch come from the `origin` remote and `HEAD`.

  ## Inputs

    * `title` — necessary. A `DomovoyCore.Type.String`.
    * `body` — necessary. A `DomovoyCore.Type.String`.
    * `base_branch` — optional. A `DomovoyCore.Type.String`. The runner reads
      `default_base_branch` from the GitHub configuration when this is absent.
    * `draft` — optional. A `DomovoyCore.Type.Boolean`. A `true` opens the pull
      request as a draft. GitHub cannot change this on an update, so the runner
      sends it only when it opens the pull request. The default is `false`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequestChange`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{title: "Implement operations", body: "Closes BRO-19.", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.CreateOrUpdatePr |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "create_or_update_pr"}
      iex> DomovoyGithubPlugin.Runner.CreateOrUpdatePr.run(input, context)
      {:ok,
       %{
         action: "created",
         number: 42,
         url: "https://github.com/theoneandonlywoj/brownie/pull/42"
       }}

  A later run changes the same pull request:

      iex> DomovoyGithubPlugin.Runner.CreateOrUpdatePr.run(input, context)
      {:ok,
       %{
         action: "updated",
         number: 42,
         url: "https://github.com/theoneandonlywoj/brownie/pull/42"
       }}
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
    field(:base_branch, StringType)
    field(:draft, BooleanType, default: false)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:title, :body, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    with {:ok, base_branch} <- base_branch(input.base_branch, input.working_directory, node_name),
         {:ok, repo} <-
           GithubCapabilities.current_repo(input.working_directory, node_name, :working_directory) do
      create_body = %{
        "title" => input.title,
        "body" => input.body,
        "head" => repo.branch,
        "base" => base_branch,
        "draft" => input.draft
      }

      update_body = %{"title" => input.title, "body" => input.body}

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

  @spec base_branch(
          base_branch :: String.t() | nil,
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, String.t()} | {:error, Error.t()}
  defp base_branch(base_branch, _directory, _node_name) when is_binary(base_branch),
    do: {:ok, base_branch}

  defp base_branch(nil, directory, node_name) do
    config_path = GithubCapabilities.find_config_path(directory)

    case GithubCapabilities.default_base_branch(config_path) do
      {:ok, base_branch} ->
        {:ok, base_branch}

      :error ->
        reason =
          "cannot create or update a pull request without a base branch; set " <>
            "default_base_branch in #{config_path} or supply base_branch"

        {:error, GithubError.create_or_update_pr_failed(reason, node_name, :base_branch)}
    end
  end

  @spec change(
          result :: {:ok, {:created | :updated, map()}} | {:error, GithubCapabilities.failure()},
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp change({:ok, {action, pull}}, _node_name),
    do: {:ok, %{action: Atom.to_string(action), number: pull["number"], url: pull["html_url"]}}

  defp change({:error, failure}, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :title)}
end
