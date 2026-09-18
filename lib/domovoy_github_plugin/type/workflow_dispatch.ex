defmodule DomovoyGithubPlugin.Type.WorkflowDispatch do
  @moduledoc """
  `DomovoyCore.Type` for a workflow that a runner started.

  GitHub does not name the run it starts. Therefore the value holds the
  `workflow` and the `ref` the runner sent, and `dispatched: true`. A caller
  that needs the run reads the newest one with `GetWorkflowRun` after a
  moment.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{workflow: "ci.yml", ref: "main", dispatched: true}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.WorkflowDispatch.dump(state)
      iex> document["dispatched"]
      true
      iex> DomovoyGithubPlugin.Type.WorkflowDispatch.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "A workflow that a runner started."
  @type state() :: %{workflow: String.t(), ref: String.t(), dispatched: true}

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{workflow: workflow, ref: ref, dispatched: true} = state, _metadata)
      when is_binary(workflow) and is_binary(ref),
      do: {:ok, state}

  def cast(_raw, _metadata), do: :error

  @keys [:workflow, :ref, :dispatched]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
