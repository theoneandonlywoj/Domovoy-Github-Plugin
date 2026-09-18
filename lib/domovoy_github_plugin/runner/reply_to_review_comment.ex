defmodule DomovoyGithubPlugin.Runner.ReplyToReviewComment do
  @moduledoc """
  Replies to a comment on a line of the diff of a pull request.

  The reply joins the thread of `comment_id`, which is the REST id of a review
  comment. `ListReviewThreads` gives that id as `comment_id`. The pull request
  is the one that `number` names, or the open one of the current branch.

  Quote the remark you answer with a `quote` block of
  `DomovoyGithubPlugin.Markdown`, so the reply reads on its own.

  ## Inputs

    * `comment_id` — necessary. A `DomovoyCore.Type.Integer`.
    * `body` — necessary. A `DomovoyGithubPlugin.Type.CommentBody`.
    * `number` — optional. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.ReviewComment`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{comment_id: 900, body: "Done in abc123.", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.ReplyToReviewComment |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "reply"}
      iex> DomovoyGithubPlugin.Runner.ReplyToReviewComment.run(input, context)
      {:ok, %{id: 901, url: "https://github.com/owner/repo/pull/42#discussion_r901", path: "lib/a.ex", line: 12}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Runner.CreateReviewComment
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType

  input do
    field(:comment_id, IntegerType)
    field(:body, CommentBodyType)
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:comment_id, :body, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, target} <-
           GithubCapabilities.resolve_pull(input.number, directory, node_name, :number) do
      target.repo.owner
      |> GithubCapabilities.reply_to_review_comment(
        target.repo.repo,
        target.number,
        input.comment_id,
        input.body,
        directory
      )
      |> CreateReviewComment.comment(node_name)
    end
  end
end
