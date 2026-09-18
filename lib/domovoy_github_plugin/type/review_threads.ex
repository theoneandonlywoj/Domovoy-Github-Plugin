defmodule DomovoyGithubPlugin.Type.ReviewThreads do
  @moduledoc """
  `DomovoyCore.Type` for the review threads of a pull request.

  A thread starts with a comment on a line of the diff. Each item holds the
  GraphQL `id` of the thread, whether it is `resolved`, whether it is
  `outdated` by a later commit, the `path` and `line`, the `body` of the
  first comment, its `author`, and the REST `comment_id` of that comment,
  which `ReplyToReviewComment` takes.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = [%{
      ...>   id: "PRRT_1", resolved: false, outdated: false, path: "lib/a.ex", line: 3,
      ...>   body: "rename this", author: "octocat", comment_id: 900
      ...> }]
      iex> {:ok, document} = DomovoyGithubPlugin.Type.ReviewThreads.dump(state)
      iex> hd(document)["resolved"]
      false
      iex> DomovoyGithubPlugin.Type.ReviewThreads.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "One review thread."
  @type thread() :: %{
          id: String.t(),
          resolved: boolean(),
          outdated: boolean(),
          path: String.t() | nil,
          line: pos_integer() | nil,
          body: String.t(),
          author: String.t() | nil,
          comment_id: pos_integer() | nil
        }

  @typedoc "The review threads of a pull request."
  @type state() :: [thread()]

  @keys [:id, :resolved, :outdated, :path, :line, :body, :author, :comment_id]

  @impl Ecto.Type
  def type, do: {:array, :map}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, _metadata) when is_list(raw) do
    if Enum.all?(raw, &thread?/1), do: {:ok, raw}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(documents), do: DomovoyCore.Type.load_each(documents, &load_thread/1)

  @spec load_thread(document :: any()) :: {:ok, thread()} | :error
  defp load_thread(document) when is_map(document) do
    thread = DomovoyCore.Type.atom_keys(document, @keys)
    if thread?(thread), do: {:ok, thread}, else: :error
  end

  defp load_thread(_document), do: :error

  @spec thread?(value :: term()) :: boolean()
  defp thread?(%{id: id, resolved: resolved, outdated: outdated, body: body} = thread)
       when is_binary(id) and is_boolean(resolved) and is_boolean(outdated) and is_binary(body),
       do: location?(thread) and commenter?(thread)

  defp thread?(_value), do: false

  @spec location?(thread :: map()) :: boolean()
  defp location?(%{path: path, line: line}),
    do: (is_binary(path) or is_nil(path)) and (is_integer(line) or is_nil(line))

  defp location?(_thread), do: false

  @spec commenter?(thread :: map()) :: boolean()
  defp commenter?(%{author: author, comment_id: comment_id}),
    do: (is_binary(author) or is_nil(author)) and (is_integer(comment_id) or is_nil(comment_id))

  defp commenter?(_thread), do: false
end
