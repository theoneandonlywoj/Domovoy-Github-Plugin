defmodule DomovoyGithubPlugin.Type.PullRequestChange do
  @moduledoc """
  `DomovoyCore.Type` for the effect of a create-or-update on a pull request.

  `action` is `"created"` when the branch had no open pull request and the
  runner opened one. `action` is `"updated"` when the runner changed a pull
  request that was already open. In both conditions the value holds the number
  and the URL of the pull request. Therefore the caller reports the result and
  does not need a second lookup.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{action: "created", number: 42, url: "https://github.com/org/repo/pull/42"}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.PullRequestChange.dump(state)
      iex> document["number"]
      42
      iex> DomovoyGithubPlugin.Type.PullRequestChange.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "What kind of create-or-update happened."
  @type action() :: String.t()

  @typedoc "The pull request a create-or-update landed on, and which it was."
  @type state() :: %{
          action: action(),
          number: integer() | nil,
          url: String.t() | nil
        }

  @actions ["created", "updated"]

  defguardp is_change(action, number, url)
            when action in @actions and (is_integer(number) or is_nil(number)) and
                   (is_binary(url) or is_nil(url))

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{action: action, number: number, url: url} = state, _metadata)
      when is_change(action, number, url) do
    {:ok, state}
  end

  def cast(_raw, _metadata), do: :error

  @keys [:action, :number, :url]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
