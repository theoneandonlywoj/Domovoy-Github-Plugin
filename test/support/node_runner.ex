defmodule DomovoyGithubPlugin.Test.NodeRunner do
  @moduledoc """
  Drives a single `DomovoyCore.Node` through its runner in tests.

  Each call creates one job and opens a FileSystem store and journal. It runs a
  one-node graph through `DomovoyCore.Engine`, so the runner uses the same path
  as production.

  ## Examples

  ```elixir
  DomovoyGithubPlugin.Test.NodeRunner.run(node, [
    {"worktree_name", DomovoyCore.Value.cast!("feature", DomovoyCore.Type.String)}
  ])
  ```
  """

  alias DomovoyCore.Context
  alias DomovoyCore.Engine
  alias DomovoyCore.Error
  alias DomovoyCore.Graph
  alias DomovoyCore.Job
  alias DomovoyCore.Journal
  alias DomovoyCore.Node
  alias DomovoyCore.Record
  alias DomovoyCore.Store
  alias DomovoyCore.Value

  @runtime DomovoyGithubPlugin.Test

  @typedoc "A dependency name paired with the result its node produced."
  @type record_pair() :: {Node.name(), Value.t() | Error.t()}

  @doc """
  Runs `node` against `inputs`, returning the `DomovoyCore.Value` or the
  `DomovoyCore.Error` of the node.

  This is a Domovoy workflow capability and has no Bash equivalent.
  """
  @spec run(node :: Node.t(), inputs :: map() | [record_pair()]) :: Value.t() | Error.t()
  def run(%Node{} = node, inputs) do
    name = node.name
    job = Job.new("test-#{System.unique_integer([:positive])}")
    root = Path.join(System.tmp_dir!(), "domovoy-github-plugin-#{job.id}")
    {:ok, store} = Store.open(Store.FileSystem, job.id, workflow: "node_runner", root: root)

    {:ok, journal} =
      Journal.open(@runtime, Journal.FileSystem, job.id, workflow: "node_runner", root: root)

    context = %Context{
      job: job,
      workflow: "node_runner",
      store: store,
      journal: journal,
      runtime: @runtime
    }

    inputs = if is_list(inputs), do: Map.new(inputs), else: inputs

    try do
      case Engine.run(Graph.new([node]), engine_inputs(inputs, job), context, in_process?: true) do
        {:ok, %{^name => %Record{result: result}}} ->
          result

        {:error, _primary_error, %{^name => %Record{status: :error, result: %Error{} = error}}} ->
          error
      end
    after
      File.rm_rf(root)
    end
  end

  @spec engine_inputs(inputs :: map(), job :: Job.t()) :: map()
  defp engine_inputs(inputs, %Job{} = job) do
    Map.new(inputs, fn
      {name, %Value{} = value} ->
        {name, value}

      {name, %Error{} = error} ->
        {name, Record.new(%{job: job, node: name, status: :error, result: error})}

      {name, %Record{} = record} ->
        {name, record}
    end)
  end
end
