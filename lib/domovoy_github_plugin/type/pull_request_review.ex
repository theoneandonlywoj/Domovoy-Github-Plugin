defmodule DomovoyGithubPlugin.Type.PullRequestReview do
  @moduledoc """
  `DomovoyCore.Type` for one review of a pull request.

  `state` is one atom. It is `:approved`, `:changes_requested`, `:commented`,
  `:dismissed`, `:pending`, or `:invalid_state`. GitHub gives the state as
  text such as `"APPROVED"`. `parse_state/1` reads that text as an atom.

  ## Examples

      iex> DomovoyGithubPlugin.Type.PullRequestReview.parse_state("CHANGES_REQUESTED")
      :changes_requested

      iex> DomovoyGithubPlugin.Type.PullRequestReview.parse_state("MERGED")
      :invalid_state

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{id: 5, state: :approved, author: "octocat", body: "", url: "u"}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.PullRequestReview.dump(state)
      iex> document["state"]
      "approved"
      iex> DomovoyGithubPlugin.Type.PullRequestReview.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @states [:approved, :changes_requested, :commented, :dismissed, :pending, :invalid_state]
  @github_states %{
    "APPROVED" => :approved,
    "CHANGES_REQUESTED" => :changes_requested,
    "COMMENTED" => :commented,
    "DISMISSED" => :dismissed,
    "PENDING" => :pending
  }

  @typedoc "The state of a review."
  @type review_state() ::
          :approved | :changes_requested | :commented | :dismissed | :pending | :invalid_state

  @typedoc "One review of a pull request."
  @type state() :: %{
          id: pos_integer(),
          state: review_state(),
          author: String.t() | nil,
          body: String.t(),
          url: String.t() | nil
        }

  @doc """
  Returns `true` if `value` is a state that this module gives.
  """
  defguard is_state(value) when value in @states

  @doc """
  Returns every state that this module gives.

  ## Examples

      iex> :approved in DomovoyGithubPlugin.Type.PullRequestReview.states()
      true
  """
  @spec states() :: [review_state()]
  def states, do: @states

  @doc """
  Reads the state text of GitHub as an atom. A text GitHub does not report
  gives `:invalid_state`.

  ## Examples

      iex> DomovoyGithubPlugin.Type.PullRequestReview.parse_state("APPROVED")
      :approved

      iex> DomovoyGithubPlugin.Type.PullRequestReview.parse_state(nil)
      :invalid_state
  """
  @spec parse_state(raw_state :: any()) :: review_state()
  def parse_state(raw_state), do: Map.get(@github_states, raw_state, :invalid_state)

  @doc """
  Returns `true` if `review` is a review as this module gives it.

  Another type that holds reviews uses this check.
  """
  @spec review?(value :: term()) :: boolean()
  def review?(%{id: id, state: state, author: author, body: body, url: url})
      when is_integer(id) and is_state(state) and (is_binary(author) or is_nil(author)) and
             is_binary(body) and (is_binary(url) or is_nil(url)),
      do: true

  def review?(_value), do: false

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, _metadata) do
    if review?(raw), do: {:ok, raw}, else: :error
  end

  @keys [:id, :state, :author, :body, :url]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(%{"state" => state} = document) when is_binary(state) do
    with {:ok, atom} <- state_atom(state) do
      document
      |> DomovoyCore.Type.atom_keys(@keys)
      |> Map.put(:state, atom)
      |> cast()
    end
  end

  def load(_document), do: :error

  @spec state_atom(text :: String.t()) :: {:ok, review_state()} | :error
  defp state_atom(text) do
    case Enum.find(@states, &(Atom.to_string(&1) == text)) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end
end
