defmodule DomovoyGithubPlugin.Type.PullRequestCommits do
  @moduledoc """
  `DomovoyCore.Type` for the commits of a pull request.

  The value is a list in the order of GitHub, which is the order of the
  branch. Each item holds the `sha`, the full `message`, and the `author`. The
  author is the GitHub login when GitHub knows it, and otherwise the name in
  the commit.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = [%{sha: "6dcb09b", message: "feat: add search", author: "octocat"}]
      iex> {:ok, document} = DomovoyGithubPlugin.Type.PullRequestCommits.dump(state)
      iex> hd(document)["sha"]
      "6dcb09b"
      iex> DomovoyGithubPlugin.Type.PullRequestCommits.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "One commit of a pull request."
  @type commit() :: %{sha: String.t(), message: String.t(), author: String.t() | nil}

  @typedoc "The commits of a pull request."
  @type state() :: [commit()]

  @keys [:sha, :message, :author]

  @impl Ecto.Type
  def type, do: {:array, :map}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, _metadata) when is_list(raw) do
    if Enum.all?(raw, &commit?/1), do: {:ok, raw}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(documents),
    do: DomovoyCore.Type.load_each(documents, &load_commit/1)

  @spec load_commit(document :: any()) :: {:ok, commit()} | :error
  defp load_commit(document) when is_map(document) do
    commit = DomovoyCore.Type.atom_keys(document, @keys)
    if commit?(commit), do: {:ok, commit}, else: :error
  end

  defp load_commit(_document), do: :error

  @spec commit?(value :: term()) :: boolean()
  defp commit?(%{sha: sha, message: message, author: author})
       when is_binary(sha) and is_binary(message) and (is_binary(author) or is_nil(author)),
       do: true

  defp commit?(_value), do: false
end
