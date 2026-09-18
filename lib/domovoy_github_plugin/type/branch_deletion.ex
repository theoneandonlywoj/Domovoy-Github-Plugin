defmodule DomovoyGithubPlugin.Type.BranchDeletion do
  @moduledoc """
  `DomovoyCore.Type` for a branch that a runner deleted from GitHub.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{branch: "feat", deleted: true}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.BranchDeletion.dump(state)
      iex> document["deleted"]
      true
      iex> DomovoyGithubPlugin.Type.BranchDeletion.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "A branch that a runner deleted."
  @type state() :: %{branch: String.t(), deleted: true}

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{branch: branch, deleted: true} = state, _metadata) when is_binary(branch),
    do: {:ok, state}

  def cast(_raw, _metadata), do: :error

  @keys [:branch, :deleted]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
