defmodule DomovoyGithubPlugin.Runner.GenerateReleaseNotes do
  @moduledoc """
  Asks GitHub to write release notes for a tag.

  GitHub writes the notes from the pull requests merged since
  `previous_tag_name`, or since the previous release. It does not make a
  release. `CreateRelease` takes the notes as its `body`.

  ## Inputs

    * `tag_name` — necessary. A `DomovoyCore.Type.String`. The tag of the
      release the notes describe. It need not exist yet.
    * `target_commitish` — optional. A `DomovoyCore.Type.String`. The branch or
      commit the tag will point at, when it does not exist.
    * `previous_tag_name` — optional. A `DomovoyCore.Type.String`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.ReleaseNotes`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{tag_name: "v1.2.0", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GenerateReleaseNotes |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "release_notes"}
      iex> DomovoyGithubPlugin.Runner.GenerateReleaseNotes.run(input, context)
      {:ok, %{name: "v1.2.0", body: "## What's Changed\\n* feat: search by @octocat in #42"}}
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

  input do
    field(:tag_name, StringType)
    field(:target_commitish, StringType)
    field(:previous_tag_name, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:tag_name, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      payload =
        %{
          "tag_name" => input.tag_name,
          "target_commitish" => input.target_commitish,
          "previous_tag_name" => input.previous_tag_name
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      repo.owner
      |> GithubCapabilities.generate_release_notes(repo.repo, payload, directory)
      |> notes(node_name)
    end
  end

  @spec notes(result :: GithubCapabilities.result(), node_name :: Node.name()) ::
          {:ok, map()} | {:error, Error.t()}
  defp notes({:ok, %{"name" => name, "body" => body}}, _node_name)
       when is_binary(name) and is_binary(body),
       do: {:ok, %{name: name, body: body}}

  defp notes({:ok, body}, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :tag_name)}

  defp notes({:error, failure}, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :tag_name)}
end
