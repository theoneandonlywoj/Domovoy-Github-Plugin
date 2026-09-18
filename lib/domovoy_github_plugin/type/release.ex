defmodule DomovoyGithubPlugin.Type.Release do
  @moduledoc """
  `DomovoyCore.Type` for a release.

  `tag_name` is the tag of the release. `draft` and `prerelease` say how
  GitHub shows it. `body` is the Markdown of the notes.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{
      ...>   id: 1,
      ...>   tag_name: "v1.2.0",
      ...>   name: "v1.2.0",
      ...>   body: "Notes",
      ...>   draft: false,
      ...>   prerelease: false,
      ...>   url: "u"
      ...> }
      iex> {:ok, document} = DomovoyGithubPlugin.Type.Release.dump(state)
      iex> document["tag_name"]
      "v1.2.0"
      iex> DomovoyGithubPlugin.Type.Release.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "A release."
  @type state() :: %{
          id: pos_integer(),
          tag_name: String.t(),
          name: String.t() | nil,
          body: String.t(),
          draft: boolean(),
          prerelease: boolean(),
          url: String.t() | nil
        }

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{id: id, tag_name: tag, name: name, body: body, url: url} = value, _metadata)
      when is_integer(id) and is_binary(tag) and (is_binary(name) or is_nil(name)) and
             is_binary(body) and (is_binary(url) or is_nil(url)) do
    if is_boolean(value[:draft]) and is_boolean(value[:prerelease]),
      do: {:ok, value},
      else: :error
  end

  def cast(_raw, _metadata), do: :error

  @keys [:id, :tag_name, :name, :body, :draft, :prerelease, :url]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
