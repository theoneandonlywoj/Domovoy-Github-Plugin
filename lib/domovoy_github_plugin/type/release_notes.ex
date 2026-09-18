defmodule DomovoyGithubPlugin.Type.ReleaseNotes do
  @moduledoc """
  `DomovoyCore.Type` for release notes that GitHub wrote.

  `name` is the title GitHub suggests. `body` is the Markdown of the notes.
  Neither is a release yet; `CreateRelease` takes them.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{name: "v1.2.0", body: "## What's Changed\\n* feat: search"}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.ReleaseNotes.dump(state)
      iex> document["name"]
      "v1.2.0"
      iex> DomovoyGithubPlugin.Type.ReleaseNotes.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "Release notes."
  @type state() :: %{name: String.t(), body: String.t()}

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{name: name, body: body} = state, _metadata) when is_binary(name) and is_binary(body),
    do: {:ok, state}

  def cast(_raw, _metadata), do: :error

  @keys [:name, :body]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
