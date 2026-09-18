defmodule DomovoyGithubPlugin.Type.Assignees do
  @moduledoc """
  `DomovoyCore.Type` for the assignees of a pull request or an issue.

  The raw value is a list of logins that are not blank. It has the shape of
  `DomovoyGithubPlugin.Type.Names`, but it is its own type. Therefore a node
  that gives assignees binds into a field that takes assignees, and a graph
  reads what the list is.

  ## Examples

      iex> DomovoyGithubPlugin.Type.Assignees.cast(["octocat"], %{})
      {:ok, ["octocat"]}

      iex> DomovoyGithubPlugin.Type.Assignees.cast("octocat", %{})
      :error
  """

  use DomovoyCore.Type

  alias DomovoyGithubPlugin.Type.Names, as: NamesType

  @typedoc "A list of logins."
  @type state() :: [String.t()]

  @impl Ecto.Type
  def type, do: {:array, :string}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, metadata), do: NamesType.cast(raw, metadata)
end
