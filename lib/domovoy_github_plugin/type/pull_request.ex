defmodule DomovoyGithubPlugin.Type.PullRequest do
  @moduledoc """
  `DomovoyCore.Type` for the result of a search for the pull request of a
  branch.

  A branch without a pull request is not an error. It is the answer. Therefore
  the value holds `state: :not_found`, and every other field is `nil`. A
  consumer reads `state`. It does not read whether the node failed.

  `state` is one atom and it gives the full answer. It is `:open`, `:closed`,
  `:merged`, `:not_found`, or `:invalid_state`. The states do not overlap.
  Therefore a consumer reads one field and never combines two.

  GitHub reports a merged pull request as closed. This type does not. A merged
  pull request is `:merged`. A pull request that a person closed without a merge
  is `:closed`.

  GitHub gives the state as text. `parse_state/2` reads that text as an atom. A
  text that GitHub does not report gives `:invalid_state`. Therefore a consumer
  matches on an atom and never on text.

  ## Examples

      iex> DomovoyGithubPlugin.Type.PullRequest.states()
      [:open, :closed, :merged, :not_found, :invalid_state]

      iex> DomovoyGithubPlugin.Type.PullRequest.merged?(%{
      ...>   state: :merged,
      ...>   number: 42,
      ...>   title: "Implement additional operations",
      ...>   body: "Closes BRO-19.",
      ...>   url: "https://github.com/theoneandonlywoj/brownie/pull/42"
      ...> })
      true

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{state: :merged, number: 7, title: "Add types", body: nil, url: "u"}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.PullRequest.dump(state)
      iex> document["state"]
      "merged"
      iex> DomovoyGithubPlugin.Type.PullRequest.load(document)
      {:ok, state}
      iex> DomovoyGithubPlugin.Type.PullRequest.load(%{document | "state" => "draft"})
      :error
  """

  use DomovoyCore.Type

  @states [:open, :closed, :merged, :not_found, :invalid_state]

  @typedoc "The state of the pull request of a branch."
  @type pull_request_state() :: :open | :closed | :merged | :not_found | :invalid_state

  @typedoc "The pull request of a branch, or the fact that there is none."
  @type state() :: %{
          state: pull_request_state(),
          number: integer() | nil,
          title: String.t() | nil,
          body: String.t() | nil,
          url: String.t() | nil
        }

  @doc """
  Returns `true` if `value` is a state that this module gives.

  Use this guard to accept a state that another module made.
  """
  defguard is_state(value) when value in @states

  defguardp is_pull_request(state, number, title, body, url)
            when is_state(state) and (is_integer(number) or is_nil(number)) and
                   (is_binary(title) or is_nil(title)) and (is_binary(body) or is_nil(body)) and
                   (is_binary(url) or is_nil(url))

  @doc """
  Returns every state that this module gives.

  ## Examples

      iex> :merged in DomovoyGithubPlugin.Type.PullRequest.states()
      true
  """
  @spec states() :: [pull_request_state()]
  def states, do: @states

  @doc """
  Reads the state text of GitHub as an atom.

  GitHub reports `"open"` or `"closed"`. GitHub reports a merged pull request as
  `"closed"` with a `"merged_at"` timestamp. Therefore this function needs both
  fields to tell a merge apart from a close. Each other value gives
  `:invalid_state`. An absent field is such a value. This function does not
  fail.

  This function never gives `:not_found`. That state says that the branch has no
  pull request at all, and it comes from an empty search result.

  ## Examples

      iex> DomovoyGithubPlugin.Type.PullRequest.parse_state("open", nil)
      :open

  A closed pull request without a timestamp was closed without a merge:

      iex> DomovoyGithubPlugin.Type.PullRequest.parse_state("closed", nil)
      :closed

  A closed pull request with a timestamp was merged:

      iex> DomovoyGithubPlugin.Type.PullRequest.parse_state(
      ...>   "closed",
      ...>   "2026-09-09T18:26:21Z"
      ...> )
      :merged

  A text that GitHub does not report gives `:invalid_state`:

      iex> DomovoyGithubPlugin.Type.PullRequest.parse_state("merged", nil)
      :invalid_state

  An absent field gives `:invalid_state`:

      iex> DomovoyGithubPlugin.Type.PullRequest.parse_state(nil, nil)
      :invalid_state
  """
  @spec parse_state(raw_state :: any(), raw_merged_at :: any()) :: pull_request_state()
  def parse_state("closed", raw_merged_at) when is_binary(raw_merged_at), do: :merged
  def parse_state("closed", _raw_merged_at), do: :closed
  def parse_state("open", _raw_merged_at), do: :open
  def parse_state(_other, _raw_merged_at), do: :invalid_state

  @doc """
  Returns `true` if the branch has a pull request that is open.

  ## Examples

      iex> DomovoyGithubPlugin.Type.PullRequest.open?(%{
      ...>   state: :open,
      ...>   number: 42,
      ...>   title: "Implement additional operations",
      ...>   body: "Closes BRO-19.",
      ...>   url: "https://github.com/theoneandonlywoj/brownie/pull/42"
      ...> })
      true
  """
  @spec open?(state()) :: boolean()
  def open?(%{state: :open}), do: true
  def open?(_state), do: false

  @doc """
  Returns `true` if the branch has a pull request that GitHub merged.

  ## Examples

      iex> DomovoyGithubPlugin.Type.PullRequest.merged?(%{
      ...>   state: :closed,
      ...>   number: 42,
      ...>   title: "Implement additional operations",
      ...>   body: "Closes BRO-19.",
      ...>   url: "https://github.com/theoneandonlywoj/brownie/pull/42"
      ...> })
      false
  """
  @spec merged?(state()) :: boolean()
  def merged?(%{state: :merged}), do: true
  def merged?(_state), do: false

  @doc """
  Returns `true` if a person closed the pull request without a merge.

  This function does not give `true` for a merged pull request. If you want each
  pull request that is no longer open, read
  `state.state in [:closed, :merged]`.

  ## Examples

      iex> DomovoyGithubPlugin.Type.PullRequest.closed?(%{
      ...>   state: :closed,
      ...>   number: 42,
      ...>   title: "Implement additional operations",
      ...>   body: "Closes BRO-19.",
      ...>   url: "https://github.com/theoneandonlywoj/brownie/pull/42"
      ...> })
      true
  """
  @spec closed?(state()) :: boolean()
  def closed?(%{state: :closed}), do: true
  def closed?(_state), do: false

  @doc """
  Returns `true` if the search found a pull request for the branch.

  ## Examples

      iex> DomovoyGithubPlugin.Type.PullRequest.found?(%{
      ...>   state: :not_found,
      ...>   number: nil,
      ...>   title: nil,
      ...>   body: nil,
      ...>   url: nil
      ...> })
      false
  """
  @spec found?(state()) :: boolean()
  def found?(%{state: :not_found}), do: false
  def found?(%{state: state}) when is_state(state), do: true
  def found?(_state), do: false

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(
        %{state: state, number: number, title: title, body: body, url: url} = raw_value,
        _metadata
      )
      when is_pull_request(state, number, title, body, url) do
    {:ok, raw_value}
  end

  def cast(_raw, _metadata), do: :error

  @keys [:state, :number, :title, :body, :url]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(%{"state" => state} = document) when is_binary(state) do
    case Enum.find(@states, &(Atom.to_string(&1) == state)) do
      nil -> :error
      found -> document |> DomovoyCore.Type.atom_keys(@keys) |> Map.put(:state, found) |> cast()
    end
  end

  def load(_document), do: :error
end
