defmodule DomovoyGithubPlugin.Type.Branch do
  @moduledoc """
  `DomovoyCore.Type` for a branch as GitHub knows it.

  `sha` is the head commit of the branch on GitHub, which may differ from the
  local one. `protected` says whether a branch protection rule applies.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{name: "main", sha: "abc123", protected: true}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.Branch.dump(state)
      iex> document["sha"]
      "abc123"
      iex> DomovoyGithubPlugin.Type.Branch.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "A branch."
  @type state() :: %{name: String.t(), sha: String.t(), protected: boolean()}

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{name: name, sha: sha, protected: protected} = state, _metadata)
      when is_binary(name) and is_binary(sha) and is_boolean(protected),
      do: {:ok, state}

  def cast(_raw, _metadata), do: :error

  @keys [:name, :sha, :protected]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
