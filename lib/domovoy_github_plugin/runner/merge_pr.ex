defmodule DomovoyGithubPlugin.Runner.MergePr do
  @moduledoc """
  Merges a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. GitHub refuses a merge when a check fails, a review is
  missing, or the branch has a conflict. The runner reports that refusal as
  `:github_pull_request_not_mergeable` and does not retry.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`. Without it the runner
      merges the open pull request of the current branch.
    * `merge_method` — optional. A `DomovoyCore.Type.String`. It is `"merge"`,
      `"squash"`, or `"rebase"`. The default is `"merge"`.
    * `commit_title` — optional. A `DomovoyCore.Type.String`.
    * `commit_message` — optional. A `DomovoyCore.Type.String`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequestMerge`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{merge_method: "squash", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.MergePr |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "merge_pr"}
      iex> DomovoyGithubPlugin.Runner.MergePr.run(input, context)
      {:ok, %{merged: true, sha: "6dcb09b", message: "Pull Request successfully merged"}}
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

  @merge_methods ["merge", "squash", "rebase"]
  @not_mergeable_statuses [405, 409]

  input do
    field(:number, IntegerType)
    field(:merge_method, StringType, default: "merge")
    field(:commit_title, StringType)
    field(:commit_message, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:merge_method, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    with {:ok, merge_method} <- validated_merge_method(input.merge_method, node_name),
         {:ok, target} <-
           GithubCapabilities.resolve_pull(
             input.number,
             input.working_directory,
             node_name,
             :number
           ) do
      payload = payload(merge_method, input.commit_title, input.commit_message)
      merge(target, payload, input.working_directory, node_name)
    end
  end

  @doc """
  Returns every merge method that the `merge_method` input accepts.

  ## Examples

      iex> DomovoyGithubPlugin.Runner.MergePr.merge_methods()
      ["merge", "squash", "rebase"]
  """
  @spec merge_methods() :: [String.t()]
  def merge_methods, do: @merge_methods

  @spec validated_merge_method(merge_method :: String.t(), node_name :: Node.name()) ::
          {:ok, String.t()} | {:error, Error.t()}
  defp validated_merge_method(merge_method, _node_name) when merge_method in @merge_methods,
    do: {:ok, merge_method}

  defp validated_merge_method(merge_method, node_name) do
    {:error,
     GithubError.invalid_merge_method(merge_method, @merge_methods, node_name, :merge_method)}
  end

  @spec payload(
          merge_method :: String.t(),
          commit_title :: String.t() | nil,
          commit_message :: String.t() | nil
        ) :: map()
  defp payload(merge_method, commit_title, commit_message) do
    %{"merge_method" => merge_method}
    |> put_present("commit_title", commit_title)
    |> put_present("commit_message", commit_message)
  end

  @spec put_present(payload :: map(), key :: String.t(), value :: String.t() | nil) :: map()
  defp put_present(payload, key, value) when is_binary(value), do: Map.put(payload, key, value)
  defp put_present(payload, _key, nil), do: payload

  @spec merge(
          target :: GithubCapabilities.target(),
          payload :: map(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp merge(target, payload, directory, node_name) do
    target.repo.owner
    |> GithubCapabilities.merge_pull(target.repo.repo, target.number, payload, directory)
    |> case do
      {:ok, %{"merged" => merged} = answer} when is_boolean(merged) ->
        {:ok, %{merged: merged, sha: answer["sha"], message: answer["message"] || ""}}

      {:ok, body} ->
        {:error, GithubError.request_failed(inspect(body), node_name, :number)}

      {:error, %{status: status, message: message}} when status in @not_mergeable_statuses ->
        {:error,
         GithubError.pull_request_not_mergeable(target.number, message, node_name, :number)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end
end
