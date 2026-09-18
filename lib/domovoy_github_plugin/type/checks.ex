defmodule DomovoyGithubPlugin.Type.Checks do
  @moduledoc """
  `DomovoyCore.Type` for the checks of a commit.

  `state` is one atom that sums up every check run and every commit status
  of the commit. It is `:pending` while any of them is still going,
  `:failure` when any of them failed, `:none` when the commit has no check
  at all, and `:success` otherwise. Therefore a consumer reads one field.

  `runs` holds the check runs, and `statuses` the commit statuses, with the
  words of GitHub. A consumer that needs the reason of a failure reads them.

  ## Examples

      iex> DomovoyGithubPlugin.Type.Checks.states()
      [:pending, :success, :failure, :none]

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{
      ...>   sha: "abc",
      ...>   state: :failure,
      ...>   runs: [%{name: "test", status: "completed", conclusion: "failure", url: "u"}],
      ...>   statuses: [%{context: "ci/lint", state: "success", url: nil}]
      ...> }
      iex> {:ok, document} = DomovoyGithubPlugin.Type.Checks.dump(state)
      iex> document["state"]
      "failure"
      iex> DomovoyGithubPlugin.Type.Checks.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @states [:pending, :success, :failure, :none]

  @typedoc "The sum of the checks of a commit."
  @type checks_state() :: :pending | :success | :failure | :none

  @typedoc "One check run."
  @type run() :: %{
          name: String.t(),
          status: String.t() | nil,
          conclusion: String.t() | nil,
          url: String.t() | nil
        }

  @typedoc "One commit status."
  @type status() :: %{context: String.t(), state: String.t() | nil, url: String.t() | nil}

  @typedoc "The checks of a commit."
  @type state() :: %{sha: String.t(), state: checks_state(), runs: [run()], statuses: [status()]}

  @keys [:sha, :state, :runs, :statuses]
  @run_keys [:name, :status, :conclusion, :url]
  @status_keys [:context, :state, :url]

  @doc """
  Returns `true` if `value` is a state that this module gives.
  """
  defguard is_state(value) when value in @states

  @doc """
  Returns every state that this module gives.
  """
  @spec states() :: [checks_state()]
  def states, do: @states

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{sha: sha, state: state, runs: runs, statuses: statuses} = value, _metadata)
      when is_binary(sha) and is_state(state) and is_list(runs) and is_list(statuses) do
    if Enum.all?(runs, &run?/1) and Enum.all?(statuses, &status?/1),
      do: {:ok, value},
      else: :error
  end

  def cast(_raw, _metadata), do: :error

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(%{"state" => text, "runs" => runs, "statuses" => statuses} = document)
      when is_binary(text) do
    with {:ok, state} <- state_atom(text),
         {:ok, runs} <- DomovoyCore.Type.load_each(runs, &load_run/1),
         {:ok, statuses} <- DomovoyCore.Type.load_each(statuses, &load_status/1) do
      document
      |> DomovoyCore.Type.atom_keys(@keys)
      |> Map.merge(%{state: state, runs: runs, statuses: statuses})
      |> cast()
    end
  end

  def load(_document), do: :error

  @spec state_atom(text :: String.t()) :: {:ok, checks_state()} | :error
  defp state_atom(text) do
    case Enum.find(@states, &(Atom.to_string(&1) == text)) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

  @spec load_run(document :: any()) :: {:ok, run()} | :error
  defp load_run(document) when is_map(document) do
    run = DomovoyCore.Type.atom_keys(document, @run_keys)
    if run?(run), do: {:ok, run}, else: :error
  end

  defp load_run(_document), do: :error

  @spec load_status(document :: any()) :: {:ok, status()} | :error
  defp load_status(document) when is_map(document) do
    status = DomovoyCore.Type.atom_keys(document, @status_keys)
    if status?(status), do: {:ok, status}, else: :error
  end

  defp load_status(_document), do: :error

  @spec run?(value :: term()) :: boolean()
  defp run?(%{name: name, status: status, conclusion: conclusion, url: url})
       when is_binary(name) and (is_binary(status) or is_nil(status)) and
              (is_binary(conclusion) or is_nil(conclusion)) and (is_binary(url) or is_nil(url)),
       do: true

  defp run?(_value), do: false

  @spec status?(value :: term()) :: boolean()
  defp status?(%{context: context, state: state, url: url})
       when is_binary(context) and (is_binary(state) or is_nil(state)) and
              (is_binary(url) or is_nil(url)),
       do: true

  defp status?(_value), do: false
end
