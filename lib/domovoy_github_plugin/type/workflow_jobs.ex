defmodule DomovoyGithubPlugin.Type.WorkflowJobs do
  @moduledoc """
  `DomovoyCore.Type` for the jobs of a workflow run.

  Each job holds its `id`, `name`, `status`, `conclusion`, and `url`, and the
  `steps` it ran. The status and conclusion words are those of GitHub, since
  a consumer reads the sum of a run from `DomovoyGithubPlugin.Type.WorkflowRun`
  and reads the jobs for the reason.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = [%{
      ...>   id: 1, name: "test", status: "completed", conclusion: "failure", url: "u",
      ...>   steps: [%{number: 1, name: "mix test", status: "completed", conclusion: "failure"}]
      ...> }]
      iex> {:ok, document} = DomovoyGithubPlugin.Type.WorkflowJobs.dump(state)
      iex> hd(document)["name"]
      "test"
      iex> DomovoyGithubPlugin.Type.WorkflowJobs.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "One step of a job."
  @type step() :: %{
          number: integer(),
          name: String.t(),
          status: String.t() | nil,
          conclusion: String.t() | nil
        }

  @typedoc "One job of a run."
  @type job() :: %{
          id: pos_integer(),
          name: String.t(),
          status: String.t() | nil,
          conclusion: String.t() | nil,
          url: String.t() | nil,
          steps: [step()]
        }

  @typedoc "The jobs of a run."
  @type state() :: [job()]

  @job_keys [:id, :name, :status, :conclusion, :url, :steps]
  @step_keys [:number, :name, :status, :conclusion]

  @impl Ecto.Type
  def type, do: {:array, :map}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, _metadata) when is_list(raw) do
    if Enum.all?(raw, &job?/1), do: {:ok, raw}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(documents), do: DomovoyCore.Type.load_each(documents, &load_job/1)

  @spec load_job(document :: any()) :: {:ok, job()} | :error
  defp load_job(%{"steps" => steps} = document) do
    with {:ok, steps} <- DomovoyCore.Type.load_each(steps, &load_step/1) do
      job = document |> DomovoyCore.Type.atom_keys(@job_keys) |> Map.put(:steps, steps)
      if job?(job), do: {:ok, job}, else: :error
    end
  end

  defp load_job(_document), do: :error

  @spec load_step(document :: any()) :: {:ok, step()} | :error
  defp load_step(document) when is_map(document) do
    step = DomovoyCore.Type.atom_keys(document, @step_keys)
    if step?(step), do: {:ok, step}, else: :error
  end

  defp load_step(_document), do: :error

  @spec job?(value :: term()) :: boolean()
  defp job?(%{id: id, name: name, status: status, conclusion: conclusion, url: url, steps: steps})
       when is_integer(id) and is_binary(name) and (is_binary(status) or is_nil(status)) and
              (is_binary(conclusion) or is_nil(conclusion)) and (is_binary(url) or is_nil(url)) and
              is_list(steps),
       do: Enum.all?(steps, &step?/1)

  defp job?(_value), do: false

  @spec step?(value :: term()) :: boolean()
  defp step?(%{number: number, name: name, status: status, conclusion: conclusion})
       when is_integer(number) and is_binary(name) and (is_binary(status) or is_nil(status)) and
              (is_binary(conclusion) or is_nil(conclusion)),
       do: true

  defp step?(_value), do: false
end
