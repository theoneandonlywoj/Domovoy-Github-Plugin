defmodule DomovoyGithubPlugin.Type.CommentKey do
  @moduledoc """
  `DomovoyCore.Type` for the key that names a comment of Domovoy.

  The key goes inside an HTML comment, `<!-- domovoy:<key> -->`, that marks
  the comment on GitHub. Therefore the key is one or more of `a-z`, `0-9`,
  `_`, and `-`. A key with a space, a `>`, or a capital letter is not a value.
  A `-->` inside the key would end the marker early, and the rest of it would
  show on the pull request.

  ## Examples

      iex> DomovoyGithubPlugin.Type.CommentKey.cast("checks", %{})
      {:ok, "checks"}

      iex> DomovoyGithubPlugin.Type.CommentKey.cast("release_notes-2", %{})
      {:ok, "release_notes-2"}

      iex> DomovoyGithubPlugin.Type.CommentKey.cast("checks -->", %{})
      :error

      iex> DomovoyGithubPlugin.Type.CommentKey.cast("", %{})
      :error
  """

  use DomovoyCore.Type

  @pattern ~r/^[a-z0-9_-]+$/

  @impl Ecto.Type
  def type, do: :string

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, _metadata) when is_binary(raw) do
    if Regex.match?(@pattern, raw), do: {:ok, raw}, else: :error
  end

  def cast(_raw, _metadata), do: :error
end
