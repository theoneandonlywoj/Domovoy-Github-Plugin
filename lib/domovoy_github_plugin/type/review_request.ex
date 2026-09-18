defmodule DomovoyGithubPlugin.Type.ReviewRequest do
  @moduledoc """
  `DomovoyCore.Type` for the reviewers that a pull request waits on.

  `reviewers` holds logins. `team_reviewers` holds team slugs. Both come from
  GitHub after the request. Therefore they hold every pending reviewer and not
  only the ones the runner added.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{number: 42, reviewers: ["octocat"], team_reviewers: [], url: "u"}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.ReviewRequest.dump(state)
      iex> document["reviewers"]
      ["octocat"]
      iex> DomovoyGithubPlugin.Type.ReviewRequest.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "The reviewers that a pull request waits on."
  @type state() :: %{
          number: pos_integer(),
          reviewers: [String.t()],
          team_reviewers: [String.t()],
          url: String.t() | nil
        }

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(
        %{number: number, reviewers: reviewers, team_reviewers: teams, url: url} = state,
        _meta
      )
      when is_integer(number) and is_list(reviewers) and is_list(teams) and
             (is_binary(url) or is_nil(url)) do
    if Enum.all?(reviewers ++ teams, &is_binary/1), do: {:ok, state}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @keys [:number, :reviewers, :team_reviewers, :url]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
