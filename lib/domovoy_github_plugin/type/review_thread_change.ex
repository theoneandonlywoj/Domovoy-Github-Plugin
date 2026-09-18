defmodule DomovoyGithubPlugin.Type.ReviewThreadChange do
  @moduledoc """
  `DomovoyCore.Type` for the effect of a runner on a review thread.

  `id` is the GraphQL id of the thread. `resolved` is its state after the
  change.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{id: "PRRT_1", resolved: true}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.ReviewThreadChange.dump(state)
      iex> document["resolved"]
      true
      iex> DomovoyGithubPlugin.Type.ReviewThreadChange.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "The thread a runner changed, and its state."
  @type state() :: %{id: String.t(), resolved: boolean()}

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{id: id, resolved: resolved} = state, _metadata)
      when is_binary(id) and is_boolean(resolved),
      do: {:ok, state}

  def cast(_raw, _metadata), do: :error

  @keys [:id, :resolved]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
