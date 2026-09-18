defmodule DomovoyGithubPlugin.Type.WorkflowRun do
  @moduledoc """
  `DomovoyCore.Type` for one run of a GitHub Actions workflow.

  `status` says whether the run is going. It is `:queued`, `:in_progress`,
  `:completed`, `:waiting`, `:requested`, `:pending`, or `:invalid_state`.
  `conclusion` says how a completed run ended. It is `nil` while the run is
  going, and then `:success`, `:failure`, `:cancelled`, `:skipped`,
  `:timed_out`, `:action_required`, `:neutral`, `:stale`,
  `:startup_failure`, or `:invalid_state`.

  ## Examples

      iex> DomovoyGithubPlugin.Type.WorkflowRun.parse_status("in_progress")
      :in_progress

      iex> DomovoyGithubPlugin.Type.WorkflowRun.parse_conclusion(nil)
      nil

      iex> DomovoyGithubPlugin.Type.WorkflowRun.parse_conclusion("exploded")
      :invalid_state

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{id: 1, name: "CI", status: :completed, conclusion: :success, url: "u", head_sha: "abc"}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.WorkflowRun.dump(state)
      iex> document["conclusion"]
      "success"
      iex> DomovoyGithubPlugin.Type.WorkflowRun.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @statuses [:queued, :in_progress, :completed, :waiting, :requested, :pending, :invalid_state]
  @conclusions [
    :success,
    :failure,
    :cancelled,
    :skipped,
    :timed_out,
    :action_required,
    :neutral,
    :stale,
    :startup_failure,
    :invalid_state
  ]

  @typedoc "Whether a run is going."
  @type run_status() ::
          :queued | :in_progress | :completed | :waiting | :requested | :pending | :invalid_state

  @typedoc "How a completed run ended."
  @type run_conclusion() ::
          nil
          | :success
          | :failure
          | :cancelled
          | :skipped
          | :timed_out
          | :action_required
          | :neutral
          | :stale
          | :startup_failure
          | :invalid_state

  @typedoc "One run of a workflow."
  @type state() :: %{
          id: pos_integer(),
          name: String.t() | nil,
          status: run_status(),
          conclusion: run_conclusion(),
          url: String.t() | nil,
          head_sha: String.t() | nil
        }

  @doc """
  Returns `true` if `value` is a status that this module gives.
  """
  defguard is_status(value) when value in @statuses

  @doc """
  Returns `true` if `value` is a conclusion that this module gives, or `nil`.
  """
  defguard is_conclusion(value) when is_nil(value) or value in @conclusions

  @doc """
  Returns every status that this module gives.
  """
  @spec statuses() :: [run_status()]
  def statuses, do: @statuses

  @doc """
  Returns every conclusion that this module gives, without `nil`.
  """
  @spec conclusions() :: [run_conclusion()]
  def conclusions, do: @conclusions

  @doc """
  Reads the status text of GitHub as an atom. A text GitHub does not report
  gives `:invalid_state`.

  ## Examples

      iex> DomovoyGithubPlugin.Type.WorkflowRun.parse_status("completed")
      :completed
  """
  @spec parse_status(raw :: any()) :: run_status()
  def parse_status(raw), do: atom(raw, @statuses, :invalid_state)

  @doc """
  Reads the conclusion text of GitHub as an atom. `nil` stays `nil`, since a
  run that is going has no conclusion. A text GitHub does not report gives
  `:invalid_state`.

  ## Examples

      iex> DomovoyGithubPlugin.Type.WorkflowRun.parse_conclusion("failure")
      :failure
  """
  @spec parse_conclusion(raw :: any()) :: run_conclusion()
  def parse_conclusion(nil), do: nil
  def parse_conclusion(raw), do: atom(raw, @conclusions, :invalid_state)

  @doc """
  Returns `true` if `run` is a run as this module gives it.

  Another type that holds runs uses this check.
  """
  @spec run?(value :: term()) :: boolean()
  def run?(%{id: id, name: name, status: status, conclusion: conclusion, url: url, head_sha: sha})
      when is_integer(id) and (is_binary(name) or is_nil(name)) and is_status(status) and
             is_conclusion(conclusion) and (is_binary(url) or is_nil(url)) and
             (is_binary(sha) or is_nil(sha)),
      do: true

  def run?(_value), do: false

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw, _metadata) do
    if run?(raw), do: {:ok, raw}, else: :error
  end

  @keys [:id, :name, :status, :conclusion, :url, :head_sha]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(%{"status" => status} = document) when is_binary(status) do
    conclusion = document["conclusion"]

    document
    |> DomovoyCore.Type.atom_keys(@keys)
    |> Map.merge(%{
      status: atom(status, @statuses, :error),
      conclusion: if(is_nil(conclusion), do: nil, else: atom(conclusion, @conclusions, :error))
    })
    |> cast()
  end

  def load(_document), do: :error

  @spec atom(raw :: any(), allowed :: [atom()], fallback :: atom()) :: atom()
  defp atom(raw, allowed, fallback) when is_binary(raw) do
    Enum.find(allowed, fallback, &(Atom.to_string(&1) == raw))
  end

  defp atom(_raw, _allowed, fallback), do: fallback
end
