defmodule DomovoyGithubPlugin.Runner.ReviewPr do
  @moduledoc """
  Submits a review of a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. `event` says what the review does: `"approve"`,
  `"request_changes"`, or `"comment"`. GitHub needs a `body` for the last
  two.

  GitHub does not let the author of a pull request approve it, and reports
  that as a failure.

  ## Inputs

    * `event` — necessary. A `DomovoyCore.Type.String`.
    * `body` — optional. A `DomovoyGithubPlugin.Type.CommentBody`.
    * `number` — optional. A `DomovoyCore.Type.Integer`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequestReview`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{event: "approve", body: "Looks good.", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.ReviewPr |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "review_pr"}
      iex> DomovoyGithubPlugin.Runner.ReviewPr.run(input, context)
      {:ok, %{id: 500, state: :approved, author: "octocat", body: "Looks good.", url: "https://github.com/owner/repo/pull/42#pullrequestreview-500"}}

  The events:

      iex> DomovoyGithubPlugin.Runner.ReviewPr.events()
      ["approve", "request_changes", "comment"]
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
  alias DomovoyGithubPlugin.Type.PullRequestReview, as: PullRequestReviewType

  @events ["approve", "request_changes", "comment"]

  input do
    field(:event, StringType)
    field(:body, CommentBodyType)
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:event, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, event} <- validated_event(input.event, node_name),
         {:ok, target} <-
           GithubCapabilities.resolve_pull(input.number, directory, node_name, :number) do
      payload = %{"event" => String.upcase(event), "body" => input.body || ""}
      review(target, payload, directory, node_name)
    end
  end

  @doc """
  Returns every event that the `event` input accepts.

  ## Examples

      iex> DomovoyGithubPlugin.Runner.ReviewPr.events()
      ["approve", "request_changes", "comment"]
  """
  @spec events() :: [String.t()]
  def events, do: @events

  @doc """
  Reads a review of GitHub as a `DomovoyGithubPlugin.Type.PullRequestReview`.

  `ListPrReviews` uses this too.

  ## Examples

      iex> DomovoyGithubPlugin.Runner.ReviewPr.review(%{
      ...>   "id" => 5,
      ...>   "state" => "APPROVED",
      ...>   "user" => %{"login" => "octocat"},
      ...>   "body" => "",
      ...>   "html_url" => "u"
      ...> })
      %{id: 5, state: :approved, author: "octocat", body: "", url: "u"}
  """
  @spec review(entry :: map()) :: PullRequestReviewType.state()
  def review(entry) when is_map(entry) do
    %{
      id: entry["id"],
      state: PullRequestReviewType.parse_state(entry["state"]),
      author: get_in(entry, ["user", "login"]),
      body: entry["body"] || "",
      url: entry["html_url"]
    }
  end

  @spec validated_event(event :: String.t(), node_name :: Node.name()) ::
          {:ok, String.t()} | {:error, Error.t()}
  defp validated_event(event, _node_name) when event in @events, do: {:ok, event}

  defp validated_event(event, node_name),
    do: {:error, GithubError.invalid_review_event(event, @events, node_name, :event)}

  @spec review(
          target :: GithubCapabilities.target(),
          payload :: map(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp review(target, payload, directory, node_name) do
    target.repo.owner
    |> GithubCapabilities.create_review(target.repo.repo, target.number, payload, directory)
    |> case do
      {:ok, %{"id" => id} = entry} when is_integer(id) -> {:ok, review(entry)}
      {:ok, body} -> {:error, GithubError.request_failed(inspect(body), node_name, :event)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :event)}
    end
  end
end
