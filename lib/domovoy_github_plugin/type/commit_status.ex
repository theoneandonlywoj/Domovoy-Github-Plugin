defmodule DomovoyGithubPlugin.Type.CommitStatus do
  @moduledoc """
  `DomovoyCore.Type` for a commit status that a runner set.

  `state` is the word of GitHub: `"error"`, `"failure"`, `"pending"`, or
  `"success"`. `context` names the status, so a later status with the same
  context replaces it.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{sha: "abc", state: "success", context: "domovoy", url: "u"}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.CommitStatus.dump(state)
      iex> document["context"]
      "domovoy"
      iex> DomovoyGithubPlugin.Type.CommitStatus.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @states ["error", "failure", "pending", "success"]

  @typedoc "A commit status."
  @type state() :: %{
          sha: String.t(),
          state: String.t(),
          context: String.t(),
          url: String.t() | nil
        }

  @doc """
  Returns every state that GitHub accepts.

  ## Examples

      iex> DomovoyGithubPlugin.Type.CommitStatus.states()
      ["error", "failure", "pending", "success"]
  """
  @spec states() :: [String.t()]
  def states, do: @states

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{sha: sha, state: state, context: context, url: url} = value, _metadata)
      when is_binary(sha) and state in @states and is_binary(context) and
             (is_binary(url) or is_nil(url)),
      do: {:ok, value}

  def cast(_raw, _metadata), do: :error

  @keys [:sha, :state, :context, :url]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
