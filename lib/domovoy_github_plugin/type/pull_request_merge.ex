defmodule DomovoyGithubPlugin.Type.PullRequestMerge do
  @moduledoc """
  `DomovoyCore.Type` for the answer of GitHub to a merge.

  `merged` says whether the merge happened. `sha` is the merge commit, or the
  head commit for a rebase or a squash. `message` is the sentence of GitHub.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{merged: true, sha: "6dcb09b", message: "Pull Request successfully merged"}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.PullRequestMerge.dump(state)
      iex> document["merged"]
      true
      iex> DomovoyGithubPlugin.Type.PullRequestMerge.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "The answer of GitHub to a merge."
  @type state() :: %{merged: boolean(), sha: String.t() | nil, message: String.t()}

  defguardp is_merge(merged, sha, message)
            when is_boolean(merged) and (is_binary(sha) or is_nil(sha)) and is_binary(message)

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{merged: merged, sha: sha, message: message} = state, _metadata)
      when is_merge(merged, sha, message),
      do: {:ok, state}

  def cast(_raw, _metadata), do: :error

  @keys [:merged, :sha, :message]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
