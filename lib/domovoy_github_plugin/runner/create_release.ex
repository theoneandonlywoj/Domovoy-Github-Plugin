defmodule DomovoyGithubPlugin.Runner.CreateRelease do
  @moduledoc """
  Makes a release in the repository of the checkout.

  GitHub makes the tag when it does not exist, at `target_commitish` or the
  default branch. With `generate_release_notes` GitHub writes the notes from
  the pull requests since the previous release, and a `body` goes above them.

  ## Inputs

    * `tag_name` — necessary. A `DomovoyCore.Type.String`.
    * `name` — optional. A `DomovoyCore.Type.String`. The title. The default
      is the tag.
    * `body` — optional. A `DomovoyGithubPlugin.Type.CommentBody`.
    * `target_commitish` — optional. A `DomovoyCore.Type.String`. The branch or
      commit the tag points at when GitHub makes it.
    * `draft` — optional. A `DomovoyCore.Type.Boolean`. The default is `false`.
    * `prerelease` — optional. A `DomovoyCore.Type.Boolean`. The default is
      `false`.
    * `generate_release_notes` — optional. A `DomovoyCore.Type.Boolean`. The
      default is `false`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Release`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{tag_name: "v1.2.0", generate_release_notes: true, working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.CreateRelease |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "create_release"}
      iex> DomovoyGithubPlugin.Runner.CreateRelease.run(input, context)
      {:ok,
       %{
         id: 1,
         tag_name: "v1.2.0",
         name: "v1.2.0",
         body: "## What's Changed",
         draft: false,
         prerelease: false,
         url: "https://github.com/owner/repo/releases/tag/v1.2.0"
       }}

  A release as GitHub reports it, read as a `DomovoyGithubPlugin.Type.Release`:

      iex> DomovoyGithubPlugin.Runner.CreateRelease.release(%{
      ...>   "id" => 1,
      ...>   "tag_name" => "v1.0.0",
      ...>   "name" => nil,
      ...>   "body" => nil,
      ...>   "draft" => true,
      ...>   "prerelease" => false,
      ...>   "html_url" => "u"
      ...> })
      %{id: 1, tag_name: "v1.0.0", name: nil, body: "", draft: true, prerelease: false, url: "u"}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType
  alias DomovoyGithubPlugin.Type.Release, as: ReleaseType

  input do
    field(:tag_name, StringType)
    field(:name, StringType)
    field(:body, CommentBodyType)
    field(:target_commitish, StringType)
    field(:draft, BooleanType, default: false)
    field(:prerelease, BooleanType, default: false)
    field(:generate_release_notes, BooleanType, default: false)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:tag_name, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      repo.owner
      |> GithubCapabilities.create_release(repo.repo, payload(input), directory)
      |> created(node_name)
    end
  end

  @doc """
  Reads a release as GitHub reports it as a `DomovoyGithubPlugin.Type.Release`.

  `GetLatestRelease` and `GetRelease` use this too.

  ## Examples

      iex> DomovoyGithubPlugin.Runner.CreateRelease.release(%{"id" => 1, "tag_name" => "v1"})
      %{id: 1, tag_name: "v1", name: nil, body: "", draft: false, prerelease: false, url: nil}
  """
  @spec release(entry :: map()) :: ReleaseType.state()
  def release(entry) when is_map(entry) do
    %{
      id: entry["id"],
      tag_name: entry["tag_name"],
      name: entry["name"],
      body: entry["body"] || "",
      draft: entry["draft"] == true,
      prerelease: entry["prerelease"] == true,
      url: entry["html_url"]
    }
  end

  @spec payload(input :: Input.t()) :: map()
  defp payload(%Input{} = input) do
    %{
      "tag_name" => input.tag_name,
      "name" => input.name,
      "body" => input.body,
      "target_commitish" => input.target_commitish,
      "draft" => input.draft,
      "prerelease" => input.prerelease,
      "generate_release_notes" => input.generate_release_notes
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec created(result :: GithubCapabilities.result(), node_name :: Node.name()) ::
          {:ok, map()} | {:error, Error.t()}
  defp created({:ok, %{"id" => id} = entry}, _node_name) when is_integer(id),
    do: {:ok, release(entry)}

  defp created({:ok, body}, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :tag_name)}

  defp created({:error, failure}, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :tag_name)}
end
