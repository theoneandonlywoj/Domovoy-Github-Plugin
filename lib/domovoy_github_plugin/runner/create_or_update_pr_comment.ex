defmodule DomovoyGithubPlugin.Runner.CreateOrUpdatePrComment do
  @moduledoc """
  Writes a conversation comment on a pull request, or replaces the one it
  wrote before.

  The comment carries a hidden marker with `key`. The first run writes the
  comment. Each later run with the same key replaces its text. Therefore a
  workflow that reports its progress keeps one comment and does not add one
  per run. The pull request is the one that `number` names, or the open one
  of the current branch.

  ## Inputs

    * `key` — necessary. A `DomovoyGithubPlugin.Type.CommentKey`. It names the
      comment. It is `[a-z0-9_-]` so the marker stays valid HTML.
    * `body` — necessary. A `DomovoyGithubPlugin.Type.CommentBody`.
    * `number` — optional. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.CommentChange`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{key: "checks", body: "All green.", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.CreateOrUpdatePrComment |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "report"}
      iex> DomovoyGithubPlugin.Runner.CreateOrUpdatePrComment.run(input, context)
      {:ok, %{action: "created", id: 1001, url: "https://github.com/owner/repo/pull/42#issuecomment-1001"}}

  The marker of a key:

      iex> DomovoyGithubPlugin.Runner.CreateOrUpdatePrComment.marker("checks")
      "<!-- domovoy:checks -->"
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
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType
  alias DomovoyGithubPlugin.Type.CommentKey, as: CommentKeyType

  input do
    field(:key, CommentKeyType)
    field(:body, CommentBodyType)
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:key, :body, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory
    text = marker(input.key) <> "\n" <> input.body

    with {:ok, target} <-
           GithubCapabilities.resolve_pull(input.number, directory, node_name, :number),
         {:ok, comments} <- comments(target, directory, node_name) do
      comments
      |> Enum.find(&marked?(&1, input.key))
      |> write(target, text, directory, node_name)
    end
  end

  @doc """
  Returns the hidden marker that names the comment of `key`.

  ## Examples

      iex> DomovoyGithubPlugin.Runner.CreateOrUpdatePrComment.marker("checks")
      "<!-- domovoy:checks -->"
  """
  @spec marker(key :: String.t()) :: String.t()
  def marker(key) when is_binary(key), do: "<!-- domovoy:" <> key <> " -->"

  @spec comments(
          target :: GithubCapabilities.target(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, [map()]} | {:error, Error.t()}
  defp comments(target, directory, node_name) do
    target.repo.owner
    |> GithubCapabilities.list_issue_comments(target.repo.repo, target.number, directory)
    |> case do
      {:ok, comments} -> {:ok, comments}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :key)}
    end
  end

  @spec marked?(comment :: map(), key :: String.t()) :: boolean()
  defp marked?(%{"body" => body}, key) when is_binary(body),
    do: String.contains?(body, marker(key))

  defp marked?(_comment, _key), do: false

  @spec write(
          existing :: map() | nil,
          target :: GithubCapabilities.target(),
          text :: String.t(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp write(nil, target, text, directory, node_name) do
    target.repo.owner
    |> GithubCapabilities.create_issue_comment(target.repo.repo, target.number, text, directory)
    |> change("created", node_name)
  end

  defp write(%{"id" => id}, target, text, directory, node_name) when is_integer(id) do
    target.repo.owner
    |> GithubCapabilities.update_issue_comment(target.repo.repo, id, text, directory)
    |> change("updated", node_name)
  end

  @spec change(
          result :: GithubCapabilities.result(),
          action :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp change({:ok, %{"id" => id} = comment}, action, _node_name) when is_integer(id),
    do: {:ok, %{action: action, id: id, url: comment["html_url"]}}

  defp change({:ok, body}, _action, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :body)}

  defp change({:error, failure}, _action, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :body)}
end
