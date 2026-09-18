defmodule DomovoyGithubPlugin.Type.PullRequestReviews do
  @moduledoc """
  `DomovoyCore.Type` for the reviews of a pull request.

  The value is a list of `DomovoyGithubPlugin.Type.PullRequestReview` values,
  oldest first.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = [%{id: 5, state: :approved, author: "octocat", body: "", url: "u"}]
      iex> {:ok, document} = DomovoyGithubPlugin.Type.PullRequestReviews.dump(state)
      iex> hd(document)["state"]
      "approved"
      iex> DomovoyGithubPlugin.Type.PullRequestReviews.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  alias DomovoyGithubPlugin.Type.PullRequestReview, as: PullRequestReviewType

  @typedoc "The reviews of a pull request, oldest first."
  @type state() :: [PullRequestReviewType.state()]

  @impl Ecto.Type
  def type, do: {:array, :map}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, _metadata) when is_list(raw) do
    if Enum.all?(raw, &PullRequestReviewType.review?/1), do: {:ok, raw}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(documents), do: DomovoyCore.Type.load_each(documents, &PullRequestReviewType.load/1)
end
