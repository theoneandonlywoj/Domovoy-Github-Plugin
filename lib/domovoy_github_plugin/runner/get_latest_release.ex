defmodule DomovoyGithubPlugin.Runner.GetLatestRelease do
  @moduledoc """
  Reads the latest release of the repository of the checkout.

  GitHub picks the newest release that is neither a draft nor a prerelease.
  A repository without one gives `:github_release_not_found`.

  ## Inputs

    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Release`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GetLatestRelease |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "latest_release"}
      iex> DomovoyGithubPlugin.Runner.GetLatestRelease.run(input, context)
      {:ok, %{id: 1, tag_name: "v1.2.0", name: "v1.2.0", body: "", draft: false, prerelease: false, url: "u"}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError
  alias DomovoyGithubPlugin.Runner.CreateRelease

  input do
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{working_directory: directory}, %Context{node: node_name}) do
    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      repo.owner
      |> GithubCapabilities.get_latest_release(repo.repo, directory)
      |> found(nil, node_name, :working_directory)
    end
  end

  @doc """
  Reads the answer of GitHub to a request for a release.

  `GetRelease` uses this too. A `404` gives `:github_release_not_found` with
  `tag`.
  """
  @spec found(
          result :: GithubCapabilities.result(),
          tag :: String.t() | nil,
          node_name :: Node.name(),
          field_name :: atom()
        ) :: {:ok, map()} | {:error, Error.t()}
  def found({:ok, %{"id" => id} = entry}, _tag, _node_name, _field_name) when is_integer(id),
    do: {:ok, CreateRelease.release(entry)}

  def found({:ok, body}, _tag, node_name, field_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, field_name)}

  def found({:error, %{status: 404}}, tag, node_name, field_name),
    do: {:error, GithubError.release_not_found(tag, node_name, field_name)}

  def found({:error, failure}, _tag, node_name, field_name),
    do: {:error, GithubError.request_failed(failure, node_name, field_name)}
end
