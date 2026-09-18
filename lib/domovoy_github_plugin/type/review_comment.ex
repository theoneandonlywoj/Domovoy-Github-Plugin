defmodule DomovoyGithubPlugin.Type.ReviewComment do
  @moduledoc """
  `DomovoyCore.Type` for a comment on a line of the diff of a pull request.

  `path` and `line` say where the comment sits. A reply in a thread keeps the
  path and line of the first comment. `line` is `nil` for a comment on a
  file that has no line, such as a deleted one.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{id: 9, url: "u", path: "lib/a.ex", line: 12}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.ReviewComment.dump(state)
      iex> document["line"]
      12
      iex> DomovoyGithubPlugin.Type.ReviewComment.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "One comment on a line of the diff."
  @type state() :: %{
          id: pos_integer(),
          url: String.t() | nil,
          path: String.t() | nil,
          line: pos_integer() | nil
        }

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{id: id, url: url, path: path, line: line} = state, _metadata)
      when is_integer(id) and (is_binary(url) or is_nil(url)) and
             (is_binary(path) or is_nil(path)) and (is_integer(line) or is_nil(line)),
      do: {:ok, state}

  def cast(_raw, _metadata), do: :error

  @keys [:id, :url, :path, :line]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
