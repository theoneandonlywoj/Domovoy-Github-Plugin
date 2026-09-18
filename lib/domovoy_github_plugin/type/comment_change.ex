defmodule DomovoyGithubPlugin.Type.CommentChange do
  @moduledoc """
  `DomovoyCore.Type` for the effect of a create-or-update on a comment.

  `action` is `"created"` when the pull request had no comment with the key
  and the runner wrote one. `action` is `"updated"` when the runner replaced
  the text of the comment that carried the key. `id` and `url` name the
  comment.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{action: "created", id: 1001, url: "https://github.com/o/r/pull/7#issuecomment-1001"}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.CommentChange.dump(state)
      iex> document["id"]
      1001
      iex> DomovoyGithubPlugin.Type.CommentChange.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "The comment a create-or-update landed on, and which it was."
  @type state() :: %{action: String.t(), id: pos_integer(), url: String.t() | nil}

  @actions ["created", "updated"]

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{action: action, id: id, url: url} = state, _metadata)
      when action in @actions and is_integer(id) and (is_binary(url) or is_nil(url)),
      do: {:ok, state}

  def cast(_raw, _metadata), do: :error

  @keys [:action, :id, :url]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
