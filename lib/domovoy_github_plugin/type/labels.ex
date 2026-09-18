defmodule DomovoyGithubPlugin.Type.Labels do
  @moduledoc """
  `DomovoyCore.Type` for the labels of a pull request or an issue.

  The raw value is a list of label names that are not blank. It has the
  shape of `DomovoyGithubPlugin.Type.Names`, but it is its own type. Therefore
  a node that gives labels binds into a field that takes labels, and a graph
  reads what the list is.

  ## Examples

      iex> DomovoyGithubPlugin.Type.Labels.cast(["bug", "help wanted"], %{})
      {:ok, ["bug", "help wanted"]}

      iex> DomovoyGithubPlugin.Type.Labels.cast([""], %{})
      :error
  """

  use DomovoyCore.Type

  alias DomovoyGithubPlugin.Type.Names, as: NamesType

  @typedoc "A list of label names."
  @type state() :: [String.t()]

  @impl Ecto.Type
  def type, do: {:array, :string}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, metadata), do: NamesType.cast(raw, metadata)
end
