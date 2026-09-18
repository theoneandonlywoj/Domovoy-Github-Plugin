defmodule DomovoyGithubPlugin.Type.Issue do
  @moduledoc """
  `DomovoyCore.Type` for an issue.

  `state` is `:open`, `:closed`, or `:invalid_state`. GitHub gives the state
  as text, and `parse_state/1` reads that text as an atom. `labels` and
  `assignees` hold names.

  ## Examples

      iex> DomovoyGithubPlugin.Type.Issue.parse_state("closed")
      :closed

      iex> DomovoyGithubPlugin.Type.Issue.parse_state("merged")
      :invalid_state

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{
      ...>   number: 9,
      ...>   title: "Bug",
      ...>   body: "It breaks.",
      ...>   state: :open,
      ...>   labels: ["bug"],
      ...>   assignees: [],
      ...>   url: "u"
      ...> }
      iex> {:ok, document} = DomovoyGithubPlugin.Type.Issue.dump(state)
      iex> document["state"]
      "open"
      iex> DomovoyGithubPlugin.Type.Issue.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @states [:open, :closed, :invalid_state]

  @typedoc "The state of an issue."
  @type issue_state() :: :open | :closed | :invalid_state

  @typedoc "An issue."
  @type state() :: %{
          number: pos_integer(),
          title: String.t(),
          body: String.t(),
          state: issue_state(),
          labels: [String.t()],
          assignees: [String.t()],
          url: String.t() | nil
        }

  @doc """
  Returns `true` if `value` is a state that this module gives.
  """
  defguard is_state(value) when value in @states

  @doc """
  Reads the state text of GitHub as an atom. A text GitHub does not report
  gives `:invalid_state`.

  ## Examples

      iex> DomovoyGithubPlugin.Type.Issue.parse_state("open")
      :open
  """
  @spec parse_state(raw :: any()) :: issue_state()
  def parse_state("open"), do: :open
  def parse_state("closed"), do: :closed
  def parse_state(_raw), do: :invalid_state

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{number: number, title: title, body: body, state: state, url: url} = value, _metadata)
      when is_integer(number) and is_binary(title) and is_binary(body) and is_state(state) and
             (is_binary(url) or is_nil(url)) do
    if names?(value[:labels]) and names?(value[:assignees]), do: {:ok, value}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @keys [:number, :title, :body, :state, :labels, :assignees, :url]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(%{"state" => text} = document) when is_binary(text) do
    case Enum.find(@states, &(Atom.to_string(&1) == text)) do
      nil -> :error
      state -> document |> DomovoyCore.Type.atom_keys(@keys) |> Map.put(:state, state) |> cast()
    end
  end

  def load(_document), do: :error

  @spec names?(value :: term()) :: boolean()
  defp names?(value), do: is_list(value) and Enum.all?(value, &is_binary/1)
end
