defmodule DomovoyGithubPlugin.Runner.ClosePr do
  @moduledoc """
  Closes a pull request.

  The pull request is the one that `number` names, or the open one of the
  current branch. A merged pull request is already closed, and GitHub reports a change of its state as a failure.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`. Without it the runner
      closes the open pull request of the current branch.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.PullRequestChange`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{number: 42, working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.ClosePr |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "close_pr"}
      iex> DomovoyGithubPlugin.Runner.ClosePr.run(input, context)
      {:ok, %{action: "closed", number: 42, url: "https://github.com/owner/repo/pull/42"}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError

  @state "closed"
  @action "closed"

  input do
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{number: number, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, target} <- GithubCapabilities.resolve_pull(number, directory, node_name, :number) do
      change_state(target, directory, node_name)
    end
  end

  @spec change_state(
          target :: GithubCapabilities.target(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp change_state(target, directory, node_name) do
    payload = %{"state" => @state}

    target.repo.owner
    |> GithubCapabilities.update_pull(target.repo.repo, target.number, payload, directory)
    |> case do
      {:ok, pull} when is_map(pull) ->
        {:ok, %{action: @action, number: pull["number"], url: pull["html_url"]}}

      {:ok, body} ->
        {:error, GithubError.request_failed(inspect(body), node_name, :number)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end
end
