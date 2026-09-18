defmodule DomovoyGithubPlugin.Type.Comments do
  @moduledoc """
  `DomovoyCore.Type` for the conversation comments of a pull request or an
  issue.

  The value is a list in the order of GitHub, oldest first. Each item holds
  the `id`, the `author` login, the Markdown `body`, and the `url`.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = [%{id: 1, author: "octocat", body: "LGTM", url: "u"}]
      iex> {:ok, document} = DomovoyGithubPlugin.Type.Comments.dump(state)
      iex> hd(document)["author"]
      "octocat"
      iex> DomovoyGithubPlugin.Type.Comments.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "One conversation comment."
  @type comment() :: %{
          id: pos_integer(),
          author: String.t() | nil,
          body: String.t(),
          url: String.t() | nil
        }

  @typedoc "The conversation comments, oldest first."
  @type state() :: [comment()]

  @keys [:id, :author, :body, :url]

  @impl Ecto.Type
  def type, do: {:array, :map}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, _metadata) when is_list(raw) do
    if Enum.all?(raw, &comment?/1), do: {:ok, raw}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(documents), do: DomovoyCore.Type.load_each(documents, &load_comment/1)

  @spec load_comment(document :: any()) :: {:ok, comment()} | :error
  defp load_comment(document) when is_map(document) do
    comment = DomovoyCore.Type.atom_keys(document, @keys)
    if comment?(comment), do: {:ok, comment}, else: :error
  end

  defp load_comment(_document), do: :error

  @spec comment?(value :: term()) :: boolean()
  defp comment?(%{id: id, author: author, body: body, url: url})
       when is_integer(id) and (is_binary(author) or is_nil(author)) and is_binary(body) and
              (is_binary(url) or is_nil(url)),
       do: true

  defp comment?(_value), do: false
end
