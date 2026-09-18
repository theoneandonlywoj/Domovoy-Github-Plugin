defmodule DomovoyGithubPlugin.Type.Names do
  @moduledoc """
  `DomovoyCore.Type` for a list of names, such as the logins of reviewers or
  the slugs of teams.

  The raw value is a list of strings. Each string is not blank. An empty list
  is a value. `dump/1` and `load/1` keep the list as it is.

  ## Examples

      iex> DomovoyGithubPlugin.Type.Names.cast(["octocat", "hubot"], %{})
      {:ok, ["octocat", "hubot"]}

      iex> DomovoyGithubPlugin.Type.Names.cast([], %{})
      {:ok, []}

      iex> DomovoyGithubPlugin.Type.Names.cast(["octocat", " "], %{})
      :error

      iex> DomovoyGithubPlugin.Type.Names.cast("octocat", %{})
      :error
  """

  use DomovoyCore.Type

  @typedoc "A list of names that are not blank."
  @type state() :: [String.t()]

  @impl Ecto.Type
  def type, do: {:array, :string}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, _metadata) when is_list(raw) do
    if Enum.all?(raw, &name?/1), do: {:ok, raw}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @spec name?(value :: term()) :: boolean()
  defp name?(value), do: is_binary(value) and String.trim(value) != ""
end
