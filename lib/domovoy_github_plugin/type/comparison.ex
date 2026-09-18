defmodule DomovoyGithubPlugin.Type.Comparison do
  @moduledoc """
  `DomovoyCore.Type` for the comparison of `head` against `base`.

  `status` is one atom: `:ahead`, `:behind`, `:identical`, `:diverged`, or
  `:invalid_state`. `ahead_by` counts the commits of `head` that `base` does
  not have, and `behind_by` the other way round.

  ## Examples

      iex> DomovoyGithubPlugin.Type.Comparison.parse_status("diverged")
      :diverged

      iex> DomovoyGithubPlugin.Type.Comparison.parse_status("sideways")
      :invalid_state

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{base: "main", head: "feat", status: :ahead, ahead_by: 3, behind_by: 0, total_commits: 3}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.Comparison.dump(state)
      iex> document["status"]
      "ahead"
      iex> DomovoyGithubPlugin.Type.Comparison.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @statuses [:ahead, :behind, :identical, :diverged, :invalid_state]

  @typedoc "How `head` relates to `base`."
  @type comparison_status() :: :ahead | :behind | :identical | :diverged | :invalid_state

  @typedoc "The comparison of two refs."
  @type state() :: %{
          base: String.t(),
          head: String.t(),
          status: comparison_status(),
          ahead_by: non_neg_integer(),
          behind_by: non_neg_integer(),
          total_commits: non_neg_integer()
        }

  @doc """
  Returns `true` if `value` is a status that this module gives.
  """
  defguard is_status(value) when value in @statuses

  @doc """
  Reads the status text of GitHub as an atom. A text GitHub does not report
  gives `:invalid_state`.

  ## Examples

      iex> DomovoyGithubPlugin.Type.Comparison.parse_status("identical")
      :identical
  """
  @spec parse_status(raw :: any()) :: comparison_status()
  def parse_status(raw) when is_binary(raw),
    do: Enum.find(@statuses, :invalid_state, &(Atom.to_string(&1) == raw))

  def parse_status(_raw), do: :invalid_state

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{base: base, head: head, status: status} = value, _metadata)
      when is_binary(base) and is_binary(head) and is_status(status) do
    if counts?(value), do: {:ok, value}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @keys [:base, :head, :status, :ahead_by, :behind_by, :total_commits]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(%{"status" => text} = document) when is_binary(text) do
    case Enum.find(@statuses, &(Atom.to_string(&1) == text)) do
      nil ->
        :error

      status ->
        document |> DomovoyCore.Type.atom_keys(@keys) |> Map.put(:status, status) |> cast()
    end
  end

  def load(_document), do: :error

  @spec counts?(value :: map()) :: boolean()
  defp counts?(%{ahead_by: ahead, behind_by: behind, total_commits: total})
       when is_integer(ahead) and is_integer(behind) and is_integer(total),
       do: true

  defp counts?(_value), do: false
end
