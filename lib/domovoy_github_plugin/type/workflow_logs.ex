defmodule DomovoyGithubPlugin.Type.WorkflowLogs do
  @moduledoc """
  `DomovoyCore.Type` for the logs archive of a workflow run on disk.

  `path` is the zip archive that the runner wrote. `bytes` is its size. A
  consumer opens the archive itself, since a log can be large.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{run_id: 1, path: "/repo/.domovoy/artifacts/workflow-run-1.zip", bytes: 2048}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.WorkflowLogs.dump(state)
      iex> document["bytes"]
      2048
      iex> DomovoyGithubPlugin.Type.WorkflowLogs.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "The logs archive of a run."
  @type state() :: %{run_id: pos_integer(), path: String.t(), bytes: non_neg_integer()}

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{run_id: run_id, path: path, bytes: bytes} = state, _metadata)
      when is_integer(run_id) and is_binary(path) and is_integer(bytes) and bytes >= 0,
      do: {:ok, state}

  def cast(_raw, _metadata), do: :error

  @keys [:run_id, :path, :bytes]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
