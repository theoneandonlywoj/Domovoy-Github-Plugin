defmodule DomovoyGithubPlugin.Type.CommentBody do
  @moduledoc """
  `DomovoyCore.Type` for the Markdown body of a comment, a review, an issue,
  or a release.

  The raw value is a string, which stays as it is, or a list of blocks that
  `DomovoyGithubPlugin.Markdown.render/1` turns into one string. Therefore a
  graph writes a comment as blocks, and a node that gives a plain string binds
  into the same field. The value is always a string.

  ## Examples

      iex> DomovoyGithubPlugin.Type.CommentBody.cast("plain text", %{})
      {:ok, "plain text"}

      iex> DomovoyGithubPlugin.Type.CommentBody.cast(
      ...>   [%{type: "heading", text: "Checks"}, %{type: "quote", text: "failed"}],
      ...>   %{}
      ...> )
      {:ok, "## Checks\\n\\n> failed"}

      iex> DomovoyGithubPlugin.Type.CommentBody.cast([%{type: "video"}], %{})
      :error

      iex> DomovoyGithubPlugin.Type.CommentBody.cast(42, %{})
      :error
  """

  use DomovoyCore.Type

  alias DomovoyGithubPlugin.Markdown

  @impl Ecto.Type
  def type, do: :string

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, _metadata) when is_binary(raw), do: {:ok, raw}
  def cast(raw, _metadata) when is_list(raw), do: Markdown.render(raw)
  def cast(_raw, _metadata), do: :error
end
