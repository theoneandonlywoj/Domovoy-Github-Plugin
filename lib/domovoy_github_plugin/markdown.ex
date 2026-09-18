defmodule DomovoyGithubPlugin.Markdown do
  @moduledoc """
  Builds the Markdown of a GitHub comment.

  Each function gives one block of text. `join/1` puts blocks together with a
  blank line between them, which is what GitHub needs between two blocks.
  `render/1` turns a list of blocks into one text. A block is a string, or a
  map with a `type` and the fields of that type:

    * `%{type: "paragraph", text: "..."}`
    * `%{type: "heading", text: "...", level: 2}`
    * `%{type: "quote", text: "..."}`
    * `%{type: "code_block", code: "...", language: "elixir"}`
    * `%{type: "details", summary: "...", body: "..."}`
    * `%{type: "table", headers: ["a", "b"], rows: [["1", "2"]]}`
    * `%{type: "checklist", items: [%{text: "...", done: false}]}`
    * `%{type: "link", text: "...", url: "..."}`
    * `%{type: "mention", login: "octocat"}`

  The keys of a block may be atoms or strings. Therefore a block that came
  from a JSON document renders the same as one written in a graph.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.render([
      ...>   %{type: "heading", text: "Review", level: 2},
      ...>   "Please look at this.",
      ...>   %{type: "quote", text: "the original\\nremark"}
      ...> ])
      {:ok, "## Review\\n\\nPlease look at this.\\n\\n> the original\\n> remark"}
  """

  @typedoc "One block of a comment: text, or a map with a `type`."
  @type block() :: String.t() | map()

  @doc """
  Quotes `text`. Each line gets a `> ` prefix, so a quoted reply keeps its
  line breaks.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.blockquote("first\\nsecond")
      "> first\\n> second"
  """
  @spec blockquote(text :: String.t()) :: String.t()
  def blockquote(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &("> " <> &1))
  end

  @doc """
  Fences `code` as a block, with `language` for the highlighter.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.code_block("IO.puts(1)", "elixir")
      "```elixir\\nIO.puts(1)\\n```"

      iex> DomovoyGithubPlugin.Markdown.code_block("plain")
      "```\\nplain\\n```"
  """
  @spec code_block(code :: String.t(), language :: String.t()) :: String.t()
  def code_block(code, language \\ "") when is_binary(code) and is_binary(language),
    do: "```" <> language <> "\n" <> code <> "\n```"

  @doc """
  Folds `body` under `summary`, so a long section stays out of the way.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.details("Logs", "line 1")
      "<details>\\n<summary>Logs</summary>\\n\\nline 1\\n\\n</details>"
  """
  @spec details(summary :: String.t(), body :: String.t()) :: String.t()
  def details(summary, body) when is_binary(summary) and is_binary(body),
    do: "<details>\n<summary>" <> summary <> "</summary>\n\n" <> body <> "\n\n</details>"

  @doc """
  Lays `rows` out under `headers`. A cell that holds `|` gets it escaped.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.table(["File", "Status"], [["a.ex", "ok"], ["b.ex", "a|b"]])
      "| File | Status |\\n| --- | --- |\\n| a.ex | ok |\\n| b.ex | a\\\\|b |"
  """
  @spec table(headers :: [String.t()], rows :: [[String.t()]]) :: String.t()
  def table(headers, rows) when is_list(headers) and is_list(rows) do
    separator = Enum.map(headers, fn _header -> "---" end)

    [headers, separator | rows]
    |> Enum.map_join("\n", &row/1)
  end

  @doc """
  Gives a heading of `level`, from 1 to 6.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.heading("Summary", 3)
      "### Summary"

      iex> DomovoyGithubPlugin.Markdown.heading("Summary")
      "## Summary"
  """
  @spec heading(text :: String.t(), level :: 1..6) :: String.t()
  def heading(text, level \\ 2) when is_binary(text) and level in 1..6,
    do: String.duplicate("#", level) <> " " <> text

  @doc """
  Mentions `login`.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.mention("octocat")
      "@octocat"
  """
  @spec mention(login :: String.t()) :: String.t()
  def mention(login) when is_binary(login), do: "@" <> login

  @doc """
  Links `text` to `url`.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.link("the run", "https://github.com/o/r/actions/runs/1")
      "[the run](https://github.com/o/r/actions/runs/1)"
  """
  @spec link(text :: String.t(), url :: String.t()) :: String.t()
  def link(text, url) when is_binary(text) and is_binary(url),
    do: "[" <> text <> "](" <> url <> ")"

  @doc """
  Lists `items` as task boxes. An item is text, or `{text, done?}`.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.checklist(["write tests", {"run them", true}])
      "- [ ] write tests\\n- [x] run them"
  """
  @spec checklist(items :: [String.t() | {String.t(), boolean()}]) :: String.t()
  def checklist(items) when is_list(items), do: Enum.map_join(items, "\n", &task/1)

  @doc """
  Joins `blocks` with a blank line between them, and drops empty ones.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.join(["## A", "", "text"])
      "## A\\n\\ntext"
  """
  @spec join(blocks :: [String.t()]) :: String.t()
  def join(blocks) when is_list(blocks) do
    blocks
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  @doc """
  Renders `blocks` into one text with `join/1`.

  Gives `:error` when a block has no `type` this module knows, or a field of
  the wrong shape.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.render(["a", %{"type" => "mention", "login" => "octocat"}])
      {:ok, "a\\n\\n@octocat"}

      iex> DomovoyGithubPlugin.Markdown.render([%{type: "video"}])
      :error
  """
  @spec render(blocks :: [block()]) :: {:ok, String.t()} | :error
  def render(blocks) when is_list(blocks) do
    blocks
    |> Enum.reduce_while({:ok, []}, fn block, {:ok, rendered} ->
      case render_block(block) do
        {:ok, text} -> {:cont, {:ok, [text | rendered]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, rendered} -> {:ok, rendered |> Enum.reverse() |> join()}
      :error -> :error
    end
  end

  def render(_blocks), do: :error

  @doc """
  Renders one block. A string is its own text.

  ## Examples

      iex> DomovoyGithubPlugin.Markdown.render_block(%{type: "code_block", code: "x", language: "sh"})
      {:ok, "```sh\\nx\\n```"}

      iex> DomovoyGithubPlugin.Markdown.render_block(%{type: "heading", text: "T", level: 9})
      :error
  """
  @spec render_block(block :: block()) :: {:ok, String.t()} | :error
  def render_block(text) when is_binary(text), do: {:ok, text}

  def render_block(%{} = block) do
    case field(block, :type) do
      type when is_binary(type) -> render_typed(type, block)
      _other -> :error
    end
  end

  def render_block(_block), do: :error

  @spec render_typed(type :: String.t(), block :: map()) :: {:ok, String.t()} | :error
  defp render_typed("paragraph", block), do: text_block(field(block, :text), & &1)

  defp render_typed("heading", block) do
    level = field(block, :level) || 2

    if level in 1..6,
      do: text_block(field(block, :text), &heading(&1, level)),
      else: :error
  end

  defp render_typed("quote", block), do: text_block(field(block, :text), &blockquote/1)

  defp render_typed("code_block", block) do
    language = field(block, :language) || ""

    if is_binary(language),
      do: text_block(field(block, :code), &code_block(&1, language)),
      else: :error
  end

  defp render_typed("details", block) do
    with {:ok, summary} <- text_block(field(block, :summary), & &1),
         {:ok, body} <- text_block(field(block, :body), & &1) do
      {:ok, details(summary, body)}
    end
  end

  defp render_typed("table", block) do
    headers = field(block, :headers)
    rows = field(block, :rows)

    if strings?(headers) and is_list(rows) and Enum.all?(rows, &strings?/1),
      do: {:ok, table(headers, rows)},
      else: :error
  end

  defp render_typed("checklist", block) do
    with {:ok, items} <- checklist_items(field(block, :items)) do
      {:ok, checklist(items)}
    end
  end

  defp render_typed("link", block) do
    with {:ok, text} <- text_block(field(block, :text), & &1),
         {:ok, url} <- text_block(field(block, :url), & &1) do
      {:ok, link(text, url)}
    end
  end

  defp render_typed("mention", block), do: text_block(field(block, :login), &mention/1)
  defp render_typed(_type, _block), do: :error

  @spec text_block(text :: term(), render :: (String.t() -> String.t())) ::
          {:ok, String.t()} | :error
  defp text_block(text, render) when is_binary(text), do: {:ok, render.(text)}
  defp text_block(_text, _render), do: :error

  @spec checklist_items(items :: term()) :: {:ok, [{String.t(), boolean()}]} | :error
  defp checklist_items(items) when is_list(items) do
    parsed = Enum.map(items, &checklist_item/1)

    if Enum.all?(parsed, &(&1 != :error)), do: {:ok, parsed}, else: :error
  end

  defp checklist_items(_items), do: :error

  @spec checklist_item(item :: term()) :: {String.t(), boolean()} | :error
  defp checklist_item(text) when is_binary(text), do: {text, false}

  defp checklist_item(%{} = item) do
    text = field(item, :text)
    done = field(item, :done) || false

    if is_binary(text) and is_boolean(done), do: {text, done}, else: :error
  end

  defp checklist_item(_item), do: :error

  @spec field(block :: map(), key :: atom()) :: term()
  defp field(block, key), do: Map.get(block, key, Map.get(block, Atom.to_string(key)))

  @spec strings?(value :: term()) :: boolean()
  defp strings?(value), do: is_list(value) and Enum.all?(value, &is_binary/1)

  @spec row(cells :: [String.t()]) :: String.t()
  defp row(cells), do: "| " <> Enum.map_join(cells, " | ", &escape_cell/1) <> " |"

  @spec escape_cell(cell :: String.t()) :: String.t()
  defp escape_cell(cell), do: String.replace(cell, "|", "\\|")

  @spec task(item :: String.t() | {String.t(), boolean()}) :: String.t()
  defp task({text, true}), do: "- [x] " <> text
  defp task({text, false}), do: "- [ ] " <> text
  defp task(text) when is_binary(text), do: "- [ ] " <> text
end
