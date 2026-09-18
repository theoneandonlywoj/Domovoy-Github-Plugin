defmodule DomovoyGithubPlugin.Runner.CreateReviewComment do
  @moduledoc """
  Writes a comment on a line of the diff of a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. The comment sits on `line` of `path` at the head commit of
  the pull request. `side` is `"RIGHT"` for the new text and `"LEFT"` for the
  old text.

  ## Inputs

    * `path` — necessary. A `DomovoyCore.Type.String`. The file in the diff.
    * `line` — necessary. A `DomovoyCore.Type.Integer`. The line in the file.
    * `body` — necessary. A `DomovoyGithubPlugin.Type.CommentBody`.
    * `side` — optional. A `DomovoyCore.Type.String`. The default is `"RIGHT"`.
    * `number` — optional. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.ReviewComment`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{path: "lib/a.ex", line: 12, body: "Rename this.", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.CreateReviewComment |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "review_comment"}
      iex> DomovoyGithubPlugin.Runner.CreateReviewComment.run(input, context)
      {:ok, %{id: 900, url: "https://github.com/owner/repo/pull/42#discussion_r900", path: "lib/a.ex", line: 12}}
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
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType

  input do
    field(:path, StringType)
    field(:line, IntegerType)
    field(:body, CommentBodyType)
    field(:side, StringType, default: "RIGHT")
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:path, :line, :body, :side, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, target} <-
           GithubCapabilities.resolve_pull(input.number, directory, node_name, :number),
         {:ok, sha} <- head_sha(target, node_name) do
      payload = %{
        "body" => input.body,
        "commit_id" => sha,
        "path" => input.path,
        "line" => input.line,
        "side" => input.side
      }

      target.repo.owner
      |> GithubCapabilities.create_review_comment(
        target.repo.repo,
        target.number,
        payload,
        directory
      )
      |> comment(node_name)
    end
  end

  @doc """
  Reads a review comment of GitHub as a `DomovoyGithubPlugin.Type.ReviewComment`.

  ## Examples

      iex> DomovoyGithubPlugin.Runner.CreateReviewComment.comment({:ok, %{"id" => 9, "html_url" => "u", "path" => "a", "line" => 1}}, "n")
      {:ok, %{id: 9, url: "u", path: "a", line: 1}}
  """
  @spec comment(result :: GithubCapabilities.result(), node_name :: Node.name()) ::
          {:ok, map()} | {:error, Error.t()}
  def comment({:ok, %{"id" => id} = entry}, _node_name) when is_integer(id),
    do: {:ok, %{id: id, url: entry["html_url"], path: entry["path"], line: entry["line"]}}

  def comment({:ok, body}, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :body)}

  def comment({:error, failure}, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :body)}

  @spec head_sha(target :: GithubCapabilities.target(), node_name :: Node.name()) ::
          {:ok, String.t()} | {:error, Error.t()}
  defp head_sha(%{pull: %{"head" => %{"sha" => sha}}}, _node_name) when is_binary(sha),
    do: {:ok, sha}

  defp head_sha(target, node_name) do
    reason = "pull request #{target.number} has no head sha"
    {:error, GithubError.request_failed(reason, node_name, :number)}
  end
end
