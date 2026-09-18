defmodule DomovoyGithubPlugin.Runner.GetRelease do
  @moduledoc """
  Reads the release of a tag in the repository of the checkout.

  A tag without a release gives `:github_release_not_found`.

  ## Inputs

    * `tag` — necessary. A `DomovoyCore.Type.String`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Release`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{tag: "v1.2.0", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GetRelease |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "get_release"}
      iex> DomovoyGithubPlugin.Runner.GetRelease.run(input, context)
      {:ok, %{id: 1, tag_name: "v1.2.0", name: "v1.2.0", body: "", draft: false, prerelease: false, url: "u"}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Runner.GetLatestRelease

  input do
    field(:tag, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:tag, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{tag: tag, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      repo.owner
      |> GithubCapabilities.get_release_by_tag(repo.repo, tag, directory)
      |> GetLatestRelease.found(tag, node_name, :tag)
    end
  end
end
