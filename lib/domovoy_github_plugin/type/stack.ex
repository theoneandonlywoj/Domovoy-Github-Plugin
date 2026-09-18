defmodule DomovoyGithubPlugin.Type.Stack do
  @moduledoc """
  `DomovoyCore.Type` for a stack of pull requests.

  A stacked pull request has the branch of another pull request as its base.
  The stack is the chain from the root, whose base is the default branch of
  the repository, down to the leaf. `pulls` holds that chain in that order.
  `current` is the number of the pull request the walk started from. `base`
  is the default branch.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{
      ...>   base: "main",
      ...>   current: 2,
      ...>   pulls: [
      ...>     %{number: 1, head: "feat-a", base: "main", url: "u1"},
      ...>     %{number: 2, head: "feat-b", base: "feat-a", url: "u2"}
      ...>   ]
      ...> }
      iex> {:ok, document} = DomovoyGithubPlugin.Type.Stack.dump(state)
      iex> document["current"]
      2
      iex> DomovoyGithubPlugin.Type.Stack.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "One pull request of a stack."
  @type entry() :: %{
          number: pos_integer(),
          head: String.t(),
          base: String.t(),
          url: String.t() | nil
        }

  @typedoc "The stack of a pull request, from the root to the leaf."
  @type state() :: %{base: String.t(), current: pos_integer(), pulls: [entry()]}

  @keys [:base, :current, :pulls]
  @entry_keys [:number, :head, :base, :url]

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{base: base, current: current, pulls: pulls} = state, _metadata)
      when is_binary(base) and is_integer(current) and is_list(pulls) do
    if Enum.all?(pulls, &entry?/1), do: {:ok, state}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(%{"pulls" => pulls} = document) when is_list(pulls) do
    with {:ok, entries} <- DomovoyCore.Type.load_each(pulls, &load_entry/1) do
      document
      |> DomovoyCore.Type.atom_keys(@keys)
      |> Map.put(:pulls, entries)
      |> cast()
    end
  end

  def load(_document), do: :error

  @spec load_entry(document :: any()) :: {:ok, entry()} | :error
  defp load_entry(document) when is_map(document) do
    entry = DomovoyCore.Type.atom_keys(document, @entry_keys)
    if entry?(entry), do: {:ok, entry}, else: :error
  end

  defp load_entry(_document), do: :error

  @spec entry?(value :: term()) :: boolean()
  defp entry?(%{number: number, head: head, base: base, url: url})
       when is_integer(number) and is_binary(head) and is_binary(base) and
              (is_binary(url) or is_nil(url)),
       do: true

  defp entry?(_value), do: false
end
