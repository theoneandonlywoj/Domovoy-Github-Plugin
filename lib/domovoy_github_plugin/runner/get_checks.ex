defmodule DomovoyGithubPlugin.Runner.GetChecks do
  @moduledoc """
  Reads the checks of a commit and sums them up in one state.

  The commit is `sha`, or `HEAD` of the checkout. The runner reads the check
  runs and the commit statuses of the commit. The result has one `state`:
  `:failure` when any check failed, `:pending` while any check is going and
  none failed, `:none` when the commit has no check, and `:success` otherwise.
  A failure wins over a check that is still going. Therefore a graph that
  gates on the checks does not wait for the rest when one already failed.

  ## Inputs

    * `sha` — optional. A `DomovoyCore.Type.String`. The default is `HEAD`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Checks`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GetChecks |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "get_checks"}
      iex> DomovoyGithubPlugin.Runner.GetChecks.run(input, context)
      {:ok,
       %{
         sha: "abc123",
         state: :success,
         runs: [%{name: "test", status: "completed", conclusion: "success", url: "u"}],
         statuses: []
       }}

  The sum of a list of check runs and a combined status:

      iex> DomovoyGithubPlugin.Runner.GetChecks.summarize([%{status: "in_progress", conclusion: nil}], "success")
      :pending

      iex> DomovoyGithubPlugin.Runner.GetChecks.summarize([%{status: "completed", conclusion: "cancelled"}], "success")
      :failure

      iex> DomovoyGithubPlugin.Runner.GetChecks.summarize([], "pending")
      :none

  A failure wins over a check that is still going:

      iex> DomovoyGithubPlugin.Runner.GetChecks.summarize(
      ...>   [%{status: "in_progress", conclusion: nil}, %{status: "completed", conclusion: "failure"}],
      ...>   "pending"
      ...> )
      :failure
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError
  alias DomovoyGithubPlugin.Type.Checks, as: ChecksType

  @failed_conclusions ["failure", "timed_out", "cancelled", "action_required", "startup_failure"]

  input do
    field(:sha, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{sha: sha, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory),
         {:ok, sha} <- sha(sha, directory, node_name),
         {:ok, runs} <- check_runs(repo, sha, directory, node_name),
         {:ok, combined} <- combined_status(repo, sha, directory, node_name) do
      statuses = combined |> Map.get("statuses") |> List.wrap() |> Enum.map(&status/1)

      {:ok,
       %{
         sha: sha,
         state: summarize(runs, combined["state"], statuses),
         runs: runs,
         statuses: statuses
       }}
    end
  end

  @doc """
  Sums up check `runs` and a `combined` commit status into one state.

  `runs` hold `status` and `conclusion` as GitHub gives them. `combined` is
  the `state` of the combined status: `"pending"`, `"success"`, or
  `"failure"`. A combined status of `"pending"` with no status at all means
  nothing, which is what GitHub reports for a commit without a status.

  The order is `:none`, then `:failure`, then `:pending`, then `:success`.
  Therefore a run that already failed gives `:failure` while another run is
  still going.

  ## Examples

      iex> DomovoyGithubPlugin.Runner.GetChecks.summarize([%{status: "completed", conclusion: "success"}], "success")
      :success

      iex> DomovoyGithubPlugin.Runner.GetChecks.summarize([%{status: "completed", conclusion: "success"}], "pending", [%{context: "ci"}])
      :pending
  """
  @spec summarize(runs :: [map()], combined :: String.t() | nil, statuses :: [map()]) ::
          ChecksType.checks_state()
  def summarize(runs, combined, statuses \\ []) do
    cond do
      runs == [] and statuses == [] -> :none
      Enum.any?(runs, &(&1.conclusion in @failed_conclusions)) -> :failure
      combined in ["failure", "error"] -> :failure
      Enum.any?(runs, &(&1.status != "completed")) -> :pending
      statuses != [] and combined == "pending" -> :pending
      true -> :success
    end
  end

  @spec sha(sha :: String.t() | nil, directory :: String.t(), node_name :: Node.name()) ::
          {:ok, String.t()} | {:error, Error.t()}
  defp sha(sha, _directory, _node_name) when is_binary(sha), do: {:ok, sha}
  defp sha(nil, directory, node_name), do: GithubCapabilities.head_sha(directory, node_name, :sha)

  @spec check_runs(
          repo :: GithubCapabilities.repo(),
          sha :: String.t(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, [map()]} | {:error, Error.t()}
  defp check_runs(repo, sha, directory, node_name) do
    case GithubCapabilities.list_check_runs(repo.owner, repo.repo, sha, directory) do
      {:ok, runs} -> {:ok, Enum.map(runs, &check_run/1)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :sha)}
    end
  end

  @spec combined_status(
          repo :: GithubCapabilities.repo(),
          sha :: String.t(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp combined_status(repo, sha, directory, node_name) do
    case GithubCapabilities.get_combined_status(repo.owner, repo.repo, sha, directory) do
      {:ok, combined} when is_map(combined) -> {:ok, combined}
      {:ok, body} -> {:error, GithubError.request_failed(inspect(body), node_name, :sha)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :sha)}
    end
  end

  @spec check_run(entry :: map()) :: map()
  defp check_run(entry) do
    %{
      name: entry["name"] || "",
      status: entry["status"],
      conclusion: entry["conclusion"],
      url: entry["html_url"]
    }
  end

  @spec status(entry :: map()) :: map()
  defp status(entry),
    do: %{context: entry["context"] || "", state: entry["state"], url: entry["target_url"]}
end
