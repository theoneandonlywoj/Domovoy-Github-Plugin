defmodule DomovoyGithubPlugin.Type.PullRequestFiles do
  @moduledoc """
  `DomovoyCore.Type` for the files that a pull request changes.

  The value is a list. Each item holds the `path`, the `status` GitHub reports
  (`"added"`, `"modified"`, `"removed"`, `"renamed"`, and others), and the
  counts of `additions`, `deletions`, and `changes`.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = [%{path: "lib/a.ex", status: "modified", additions: 3, deletions: 1, changes: 4}]
      iex> {:ok, document} = DomovoyGithubPlugin.Type.PullRequestFiles.dump(state)
      iex> hd(document)["path"]
      "lib/a.ex"
      iex> DomovoyGithubPlugin.Type.PullRequestFiles.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "One file that a pull request changes."
  @type file() :: %{
          path: String.t(),
          status: String.t(),
          additions: non_neg_integer(),
          deletions: non_neg_integer(),
          changes: non_neg_integer()
        }

  @typedoc "The files that a pull request changes."
  @type state() :: [file()]

  @keys [:path, :status, :additions, :deletions, :changes]

  @impl Ecto.Type
  def type, do: {:array, :map}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, _metadata) when is_list(raw) do
    if Enum.all?(raw, &file?/1), do: {:ok, raw}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(documents),
    do: DomovoyCore.Type.load_each(documents, &load_file/1)

  @spec load_file(document :: any()) :: {:ok, file()} | :error
  defp load_file(document) when is_map(document) do
    file = DomovoyCore.Type.atom_keys(document, @keys)
    if file?(file), do: {:ok, file}, else: :error
  end

  defp load_file(_document), do: :error

  @spec file?(value :: term()) :: boolean()
  defp file?(%{
         path: path,
         status: status,
         additions: additions,
         deletions: deletions,
         changes: changes
       })
       when is_binary(path) and is_binary(status) and is_integer(additions) and
              is_integer(deletions) and is_integer(changes),
       do: true

  defp file?(_value), do: false
end
